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
search_for="\s\b(ERR|Err|error|alert|crit|fatal|FATAL|MODULAR|HANDLER|TASK|PLAY|Unexpected|FAIL|[Ff]ail|denied|non-zero|[Tt]imed?\s?out|UNCAUGHT|EXCEPTION|[Aa]ssertion|panic)"

drop="Skipping because of failed dependencies|skipping:|No such (cont|image)|Cannot kill cont|Object audit|consider using the|already in this config|xconsole|CRON|multipathd|BIOS|ACPI|acpi|MAC|Error downloading|NetworkManager|ing AMQP connection|trailing slashes|wget:|root.log|Installation finished|PROPERTY NAME|INVALID|errors[:=]0|udevd|crm_element_value:|__add_xml_object:|Could not load host|MemoryDenyWriteExecute|D-Bus connection|find remote ref|eprecate|blob unknown|error None|has failures|scss\.|DEBUG|password check failed|Failed password for|Traceback|etlink|server gave HTTP response to HTTPS client|fatal_exception_format_errors|Unexpected end of command stream|authentication failure|0 fail|[Ii]nfo:|[Dd]ebug:|[Nn]otice:|[Dd]ocker[-\s][Ss]torage|pcspkr|JSchException|conversation failed|\d+\sERROR\s[\w\.]+\s+($|[^\[])|reverse mapping checking|augenrules.*failure|timeout(\s+)?=|fail\S+?(\s+)?="

echeck_verified_ignore="Error connecting to cluster|socket failed to listen on sockets|socket entered failed state|Failed to listen on Erlang|Unknown lvalue|virConnectOpenReadOnly failed|read-function of plugin|libvirt: XML-RPC error|MessagingTimeout: Timed out waiting for a reply|object has no attribute|Compute host centos|Could not open logfile|Ignoring these errors is likely to lead to a failed deploy|Connection reset by peer|Failed none for invalid user|keytab is nonexistent|Unable to process extensions|NOT_FOUND.*vhost|Failed to add dependency on|avc.*object\.recon|Unhandled error: OperationalError|ComputeHostNotFound_Remote|[Gg]lean|Failed to canonicalize path|Failure! The validation failed|test has failed as expected|Task '.*requirements' failed"

# a relaxed timestamp format, matching the mutated forms, like .py provides
rfc3339="\d{4}\-\d{2}\-\d{2}T\d{2}\:\d{2}\:\d{2}(\.[0-9]{3,9}Z?)?(\+\d{2}\:\d{2})?"
rfc3164="\w{3}\s+?\d{1,2}\s\d{2}:\d{2}:\d{2}"
ts="${rfc3339}"
tabs=31
nodemask="node\-[0-9]+"

# mutators for perl -pe
# make python logging timestamps sortable alongside generic rfc3339 timestamps
py_to_rfc3339='s/(\d{4}\-\d{2}\-\d{2})\s(\d{2}.*)$/\1T\2/'
# decode epoch from avc events into rfc3164 format
avc_to_rfc3164='s/^(.*):(type=AVC msg=audit\((\S+)\..*)$// && print("$1:",join(" ",(split(" ",scalar(localtime($3))))[1..3])," $2")'
# translate some of the messages, journald/docker and other events logged with rfc3164 into rfc3339
rfc3164_to_rfc3339='s/^(\S+:)(\w{3}\s+?\d{1,2}\s\d{2}:\d{2}:\d{2})(.*time="(\S+)".*)$/\1\4 \3/'

usage(){
  cat << EOF
  Usage:
    -h - print this usage info
    -n x - give a custom node names mask
           default is: ${nodemask}. Use '.*'
           to match arbitrary sources/files
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
pf='';pt=''
while (( $# )); do
  case "$1" in
    '-h') usage >&2; exit 0 ;;
    '-n') shift; nodemask="${1}" ;;
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

# generic stuff from logs snapshot /var/log/remote/* with "mutators" applied
grep -HEIr "${search_for}" . |\
  perl -pe "${py_to_rfc3339}" |\
  perl -pe "${avc_to_rfc3164}" |\
  perl -pe "${rfc3164_to_rfc3339}" |\
  perl -n -e "m/(?<node>${nodemask})(\.\S+)?\/?(?<file>(\.\S+))?\:(?<time>${ts})(?<rest>.*$)/ && printf (\"%${tabs}s%22s%28s%1s\n\",\"$+{time} \",\"$+{node} \",\"$+{file} \",\"$+{rest}\")" | grep -vP "${drop}" | sort > "${out}"

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
