#!/bin/bash
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# NOTE: \d+\sERROR\s[\w\.]+\s+($|[^\[) matches python traceback lines and dropped.
search_for="\s\b(E[rR]{2}:?|alert|crit|fatal|MODULAR|HANDLER|TASK|PLAY|Unexpected|FAIL|[Ff]ail|denied|non-zero|[Tt]imed?\s?out|UNCAUGHT|EXCEPTION|Unknown|[Aa]ssertion|in use)"
drop="Skipping because of failed dependencies|skipping:|No such (cont|image)|Cannot kill cont|Object audit|consider using the|already in this config|xconsole|CRON|multipathd|BIOS|ACPI|acpi|MAC|Error downloading|NetworkManager|INFO|ing AMQP connection|trailing slashes|wget:|root.log|Installation finished|PROPERTY NAME|INVALID|errors[:=]0|udevd|crm_element_value:|__add_xml_object:|Could not load host|MemoryDenyWriteExecute|D-Bus connection|find remote ref|eprecate|blob unknown|WARN|error None|[Ww]arning:|has failures|Err(no)? (http|2|11[13]|104)|scss\.|DEBUG|password check failed|Failed password for|Traceback|etlink|server gave HTTP response to HTTPS client|fatal_exception_format_errors|Unexpected end of command stream|authentication failure|0 fail|[Ii]nfo:|[Dd]ebug:|[Nn]otice:|[Dd]ocker[-\s][Ss]torage|pcspkr|JSchException|conversation failed|\d+\sERROR\s[\w\.]+\s+($|[^\[])"
echeck_verified_ignore="Error connecting to cluster|socket failed to listen on sockets|socket entered failed state|Failed to listen on Erlang|Unknown lvalue|Broken pipe|virConnectOpenReadOnly failed|read-function of plugin|libvirt: XML-RPC error|MessagingTimeout: Timed out waiting for a reply|object has no attribute|Compute host centos|Could not open logfile|Ignoring these errors is likely to lead to a failed deploy|Connection reset by peer|Failed none for invalid user"

# a relaxed timestamp format, matching the mutated forms, like .py provides
rfc3339="\d{4}\-\d{2}\-\d{2}T\d{2}\:\d{2}\:\d{2}(\.[0-9]{3,6}Z?)?(\+\d{2}\:\d{2})?"
rfc3164="\w{3}\s+?\d{1,2}\s\d{2}:\d{2}:\d{2}"
ts="${rfc3339}"
tabs=31
nodemask="node\-[0-9]+"

# mutators for perl -pe
# make python logging timestamps sortable alongside generic rfc3339 timestamps
py_to_rfc3339='s/(\d{4}\-\d{2}\-\d{2})\s(\d{2}.*)$/\1T\2/'
# decode epoch from avc events into rfc3369 format
avc_to_rfc3164='s/^(.*):(type=AVC msg=audit\((\S+)\..*)$// && print("$1:",join(" ",(split(" ",scalar(localtime($3))))[1..3])," N/A $2")'
# make journald records with rfc3164 sortable alongside generic rfc3339 timestamps
journald_rfc3164_to_rfc3339='' #TBD

usage(){
  cat << EOF
  Usage:
    -h - print this usage info
    -n x - give a custom node names mask
           default is: ${nodemask}. Use '.*'
           to match arbitrary sources/files
    -d - use fuel orchestration events parser
    -2 - use atop formatted events parser
    -f x - cut events to start from value x
    -t x - cut events to end up to value x
    -rfc3339 - use rfc3339 parser with
               .py and avc timestamps mutated
    -rfc3164 - use only rfc3164 parser
    (-s) x - search for x instead of the
           default search: ${search_for}
    -x y - add y to exclude from search list
           default exclude list is: ${drop}
    -echeck - also exclude patterns proved
              to be likely non-faily, which is
              build_status > 50% SUCCESS
              reported by elastic-recheck-query
    -xoff - disable the default/echeck drop lists
EOF
}

[[ "$#" = "0" ]] && usage
pd=1;p1=1;p2=1;pf='';pt='';fx=1;generic=0
while (( $# )); do
  case "$1" in
    '-h') usage >&2; exit 0 ;;
    '-d') generic=1; pd=0 ;;
    '-n') shift; nodemask="${1}" ;;
    '-2') generic=1; p2=0 ;;
    '-f') shift; pf="${1}" ;;
    '-t') shift; pt="${1}" ;;
    '-rfc3339') ts="${rfc3339}"; tabs=31 ;;
    '-rfc3164') ts="${rfc3164}"; tabs=15 ;;
    '-x') shift; drop="${drop}|${1}" ;;
    '-echeck') drop="${drop}|${echeck_verified_ignore}" ;;
    '-xoff') drop="dropabsolutelynothing" ;;
    '-s') shift; search_for="${1}" ;;
    *) search_for="${1}" ;;
  esac
  shift
done

echo USE search $search_for >&2
echo USE exclude $drop >&2
out=$(mktemp /tmp/tmp.XXXXXXXXXX)
out2=$(mktemp /tmp/tmp.XXXXXXXXXX)
trap 'rm -f ${out} ${out2}' EXIT INT HUP

# fuel orchestration
[[ $pd -eq 0 ]] && search_for="Spent |Puppet run failed|Error running RPC|Processing RPC call|Starting OS provisioning|step.*offset"

# atop stuff (TODO rework with perl)
[[ $p2 -eq 0 ]] && (echo "Date Time Node Running(sec) PID Exit_code PPID filename PRG_headers_as_is" && grep -HEr "${search_for}" . |\
  awk -v n=$nodemask --posix "match($0, /[0-9]{4}\/[0-9]{2}\/[0-9]{2} [0-9]{2}\:[0-9]{2}\:[0-9]{2}/, m) match($0, /$n/, n) {if (m[0] && n[0]) print m[0],n[0],$3-$15,$7,$14,$(NF-11),$0}" |\
  sort | column -t > "${out}")

# generic stuff from logs snapshot /var/log/remote/* with "mutators" applied
[[ $generic -eq 0 ]] && (grep -HEIr "${search_for}" . |\
  perl -pe "${py_to_rfc3339}" |\
  perl -pe "${avc_to_rfc3164}" |\
  perl -n -e "m/(?<node>${nodemask})(\.\S+)?\/(?<file>\S+)(\.log)?\:(?<time>${ts})(?<rest>.*$)/ && printf (\"%${tabs}s%22s%28s%1s\n\",\"$+{time} \",\"$+{node} \",\"$+{file} \",\"$+{rest}\")" | grep -vP "${drop}" | sort > "${out}")

# apply from / to
if [[ "${pf}" ]]; then
  echo USE FROM $pf >&2
  from="${pf}" perl -lne '$_=~s/^\s+//;print if ($ENV{'from'} le (split / /, $_, 1)[0])' <"${out}" >"${out2}"
  cp -f "${out2}" "${out}"
fi
if [[ "${pt}" ]]; then
  echo USE TO $pt >&2
  to="${pt}" perl -lne '$_=~s/^\s+//;print if ($ENV{'to'} ge (split / /, $_, 1)[0])' <"${out}"
else
  cat "${out}"
fi
