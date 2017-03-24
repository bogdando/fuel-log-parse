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

search_for="\s\b(Err|err|alert|Traceback|TRACE|crit|fatal|MODULAR|HANDLER|TASK|PLAY|Unexpected|FAILED)"
drop="skipping:|No such cont|Cannot kill cont|Object audit|consider using the|already in this config|xconsole|CRON|multipathd|BIOS|ACPI|MAC|Error downloading|NetworkManager|INFO REPORT|accepting AMQP connection|closing AMQP connection|trailing slashes removed|Err http|wget:|root.log|Installation finished|PROPERTY NAME|INVALID|errors: 0|udevd|crm_element_value:|__add_xml_object:|Could not load host"
rfc3339="\d{4}\-\d{2}\-\d{2}T\d{2}\:\d{2}\:\d{2}(\.[0-9]{6})?(\+\d{2}\:\d{2})?"
rfc3164="\w{3}\s+\d{1,2}\s\d{2}:\d{2}:\d{2}"
py="\d{4}\-\d{2}\-\d{2}\s\d{2}\:\d{2}\:\d{2}([,\.]\d{3,6})?"
ts="${rfc3339}|${py}"
tabs=31
nodemask="node\-[0-9]+"

usage(){
  cat << EOF
  Usage:
    -h - print this usage info
    -n x - give a custom node names mask
           default is: ${nodemask}
    -d - use fuel orchestration events parser
    -g - use generic logs format parser
    -2 - use atop formatted events parser
    -f x - cut events to start from value x
    -t x - cut events to end up to value x
    -py - parse only python-like timestamps
    -rfc3339 - use only rfc3339 parser (-py
             plus 3339 will match by default)
    -rfc3164 - use only rfc3164 parser
    (-s) x - search for x
           default search is: ${search_for}
    -x y - add y to exclude from search list
           default exclude list is: ${drop}
EOF
}

[[ "$#" = "0" ]] && usage
pd=1;p1=1;p2=1;pf='';pt='';fx=1;generic=0
while (( $# )); do
  case "$1" in
    '-h') usage >&2; exit 0 ;;
    '-d') generic=1; pd=0 ;;
    '-n') shift; nodemask="${1}" ;;
    '-g') generic=1; p1=0 ;;
    '-2') generic=1; p2=0 ;;
    '-f') shift; pf="${1}" ;;
    '-t') shift; pt="${1}" ;;
    '-rfc3339') shift; ts="${rfc3339}"; tabs=31 ;;
    '-rfc3164') shift; ts="${rfc3164}"; tabs=15 ;;
    '-py') shift; ts="${py}"; tabs=23 ;;
    '-x') shift; drop="${drop}|${1}" ;;
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

# nailgun python things
[[ $p1 -eq 0 ]] && (grep -HEr "${search_for}" .| perl -p -e "s/\S*^([^\ T]+)\s/\1T/" |\
  perl -n -e "m/(?<file>\S+)(\.log)?\:(?<time>${ts})(?<rest>.*$)/ && printf (\"%${tabs}s%28s%1s\n\",\"$+{time} \",\"$+{file} \",\"$+{rest}\")" | egrep -v "${drop}" | sort > "${out}")

# atop stuff (TODO rework with perl)
[[ $p2 -eq 0 ]] && (echo "Date Time Node Running(sec) PID Exit_code PPID filename PRG_headers_as_is" && grep -HEr "${search_for}" . |\
  awk -v n=$nodemask --posix "match($0, /[0-9]{4}\/[0-9]{2}\/[0-9]{2} [0-9]{2}\:[0-9]{2}\:[0-9]{2}/, m) match($0, /$n/, n) {if (m[0] && n[0]) print m[0],n[0],$3-$15,$7,$14,$(NF-11),$0}" |\
  sort | column -t > "${out}")

# generic stuff from logs snapshot /var/log/remote/*
[[ $generic -eq 0 ]] && (grep -HEIr "${search_for}" . |\
  perl -n -e "m/(?<node>${nodemask})(\.\S+)?\/(?<file>\S+)(\.log)?\:(?<time>${ts})(?<rest>.*$)/ && printf (\"%${tabs}s%22s%28s%1s\n\",\"$+{time} \",\"$+{node} \",\"$+{file} \",\"$+{rest}\")" | egrep -v "${drop}" | sort > "${out}")

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
