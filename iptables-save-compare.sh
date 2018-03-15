#!/bin/bash
set -eu
set -o pipefail

usage(){
  cat << EOF
  Compare a two given iptables-save dumps.
  It always strips off the matched packets counter numbers.
  Optionally, it can strip comments and sort rules as well.

  Usage:
    -h - print this usage info
    -s - remove comments and sort rules in tables
    -t - print diff for a given table only
    
  Example:
    $ sudo iptables-save|tee foo
    $ ./iptables-save-compare.sh -s \
      ./foo /etc/sysconfig/iptables
    $ less _iptables_save_compare.log
EOF
exit 1
}

if test -t 1 ; then
  echo "## Storing stdout to ./_iptables_save_compare.log"
  exec >  >(tee -i _iptables_save_compare.log )
fi
[[ "$#" -lt "2" ]] && usage

while (( $# )); do
  case "$1" in
    '-h') usage >&2; exit 0 ;;
    '-t') shift; table=$1 ;;
    '-s') superpower=yes ;;
    *) src_file=$1; shift; dst_file=$1 ;;
  esac
  shift
done

function get_diff(){
  # Apply the wanted sort/strip modes over each table in a
  # given list $1, then get a diff for rules in tables of the
  # global src_file vs dst_file. Or just dump rules from $2.
  local t
  for t in $(echo $1); do
    if [ -z "${2:-}" ]; then
      if [ "${superpower:-}" ]; then
        echo "=== Diff for the table: $t (sorted, counters and comments removed) ==="
        diff -Nuar \
        <(cat $src_file|sed -n "/^\*${t}/,/^\*/p"|sed -r '/^(#\s|\*)/d; s,(.*)\[\S+\],#\1,; s,(.*)(\-m comment \-\-comment.*)(\-.*$),\1\3,'|sort -u) \
        <(cat $dst_file|sed -n "/^\*${t}/,/^\*/p"|sed -r '/^(#\s|\*)/d; s,(.*)\[\S+\],#\1,; s,(.*)(\-m comment \-\-comment.*)(\-.*$),\1\3,'|sort -u) \
        ||:
      else
        echo "=== Diff for the table: $t (counters removed, ordering preserved) ==="
        diff -Nuar \
        <(cat $src_file|sed -n "/^\*${t}/,/^\*/p"|sed -r '/^(#\s|\*)/d; s,(.*)\[\S+\],#\1,') \
        <(cat $dst_file|sed -n "/^\*${t}/,/^\*/p"|sed -r '/^(#\s|\*)/d; s,(.*)\[\S+\],#\1,') \
        ||:
      fi
      echo
    else
      echo "=== Dump rules for the table $t in $2 (as is) ==="
      cat $2|sed -n "/^\*${t}/,/^\*/p"|sed '$ d'|sed -r '/^#\s/d; s,(.*)\[\S+\],#\1,'
      echo
    fi
  done
}

src=$(cat $src_file|sed -r '/^#\s/d; s,(.*)\[\S+\],#\1,')
dst=$(cat $dst_file|sed -r '/^#\s/d; s,(.*)\[\S+\],#\1,') 

if [ -z "${table:-}" ]; then
  src_tables=$(grep -E '^\*\S+' ${src_file}|sort)
  dst_tables=$(grep -E '^\*\S+' ${dst_file}|sort)

  tables_diff=$(diff -Nuar <(printf '%b\n' $src_tables) <(printf '%b\n' $dst_tables)||:)
  src_tables_diff=$(printf '%b\n' $tables_diff| sed -rn 's,^\-{1}\*(\S+)$,\1,p')
  dst_tables_diff=$(printf '%b\n' $tables_diff| sed -rn 's,^\+{1}\*(\S+)$,\1,p')
  common_tables=$(printf '%b\n' $tables_diff|sed -rn 's,^(\*\S+)$,\1,p')
else
  common_tables=$table
fi

printf '%b\n' "### Only comparing inputs against the common tables:\n$common_tables"
echo "(diff '-' means: not found in $dst_file)"
echo "(diff '+' means: not found in $src_file)"
echo
get_diff "$common_tables"

if [ "${src_tables_diff:-}" ]; then
  echo "### Found unique tables in $src_file: $src_tables_diff"
  echo "### Dumping rules for unique tables in $src_file"
  get_diff "$src_tables_diff" $src_file
fi

if [ "${dst_tables_diff:-}" ]; then
  echo "### Found unique tables in $dst_file: $dst_tables_diff"
  echo "### Dumping rules for unique tables in $dst_file"
  get_diff "$dst_tables_diff" $dst_file
fi
