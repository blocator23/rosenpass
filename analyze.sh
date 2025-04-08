#!/usr/bin/env bash

exc() {
  echo >&2 "\$" "$@"
  "$@"
}

run_proverif() {
  local file; file="$1"; shift
  local log; log="$1"; shift
  exc proverif -test "${@}" "${file}" 2>&1
}

clean_warnings() {
   awk '
      BEGIN {
        null = "0455290a-50d5-4f28-8008-3d69605c2835"
        p = null;
      }

      function pt(arg) {
        if (arg != null) {
          print(arg);
        }
      }
      function bod() {
        if ($0 !~ /^Warning: identifier \w+ rebound.$/) {
          pt(p);
          p=$0;
        } else {
          p=null;
        }
      }
      { bod(); }
      END { $0=null; bod(); }
    ' 
}

color_red='\033[0;31m'
color_green='\033[0;32m'
color_gray='\033[0;30m'
color_clear='\033[0m'

checkmark="✔"
cross="❌"

pretty_output_line() {
  local prefix; prefix="$1"; shift
  local mark; mark="$1"; shift
  local color; color="$1"; shift
  local text; text="$1"; shift
  echo -ne "\033[0\r${color_gray}${prefix}${color}${mark} ${text}${color_clear}"
}

pretty_output() {
  local file; file="$1"; shift
  local expected=() descs=()

  # Lemmas are processed first
  readarray -t -O "${#expected[@]}" expected < <(
    < "$file" grep -Po '@(lemma)(?=\s+"[^\"]*")' \
      | sed 's/@lemma/true/')
  readarray -t -O "${#descs[@]}" descs < <(
    < "$file" grep -Po '@(lemma)\s+"[^\"]*"' \
      | sed 's/@\w\+\s\+//; s/"//g')

  # Then regular queries
  readarray -t -O "${#expected[@]}" expected < <(
    < "$file" grep -Po '@(query|reachable)(?=\s+"[^\"]*")' \
      | sed 's/@query/true/; s/@reachable/false/')
  readarray -t -O "${#descs[@]}" descs < <(
    < "$file" grep -Po '@(query|reachable)\s+"[^\"]*"' \
      | sed 's/@\w\+\s\+//; s/"//g')
  
  local outp ctr res ta tz; ctr=0; res=0; ta="$(date +%s)"
  while read -r outp; do
    tz="$(date +%s)"
    if [[ "${outp}" = "${expected[$ctr]}" ]]; then
      pretty_output_line "$((tz - ta))s " "${checkmark}" "${color_green}" "${descs[$ctr]}"
    else
      res=1
      pretty_output_line "$((tz - ta))s " "${cross}" "${color_red}" "${descs[$ctr]}"
    fi
    echo

    (( ctr += 1 ))
    ta="${tz}"
  done

  return "$res"
}

metaverif() {
  local file; file="$1"; shift
  local name; name="$(echo "${file}" | grep -Po '[^/]*(?=\.mpv)')"

  local cpp_prep; cpp_prep="${tmpdir}/${name}.i.pv"
  exc cpp -P -I"${PWD}/$(dirname "${file}")" "${file}" -o "${cpp_prep}"

  local awk_prep; awk_prep="${tmpdir}/${name}.o.pv"
  {
    exc awk -f marzipan/marzipan.awk "${cpp_prep}" 
    echo -e "\nprocess main"
  } > "${awk_prep}"

  local log; log="${tmpdir}/${name}.log"
  {
    run_proverif "${awk_prep}" "$@" \
      | clean_warnings \
      | tee "${log}" \
      | awk '
          /^RESULT/ {
            gsub(/\./, "", $NF);
            print($NF);
            fflush(stdout);
          }' \
      | pretty_output "${cpp_prep}"
  } || {
    if ! grep -q "^Verification summary" "${log}"; then
      echo -ne "\033[0\r"
      cat "${log}"
    fi
  }
}

main() {
  set -e -o pipefail
  cd "$(dirname "$0")"
  tmpdir="target/proverif"
  mkdir -p "${tmpdir}"

  entries=()
  readarray -t -O "${#entries[@]}" entries < <(
    find analysis -iname '*.entry.mpv' | sort)
  
  local entry
  local procs; procs=()
  for entry in "${entries[@]}"; do
    exc metaverif "${entry}" "$@" >&2 & procs+=("$!")
  done

  for entry in "${procs[@]}"; do
    exc wait -f "${entry}"
  done
}

main "$@"
