#!/bin/bash

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

failed=0

report_forbidden_path() {
  echo "error: $1 local data file: $2" >&2
  failed=1
}

is_forbidden_path() {
  local lower_path
  lower_path=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower_path" in
    *.db|*.db-shm|*.db-wal|*.sqlite|*.sqlite-shm|*.sqlite-wal|*.sqlite3|*.sqlite3-shm|*.sqlite3-wal|*.zip)
      return 0
      ;;
    dict*.txt|*/dict*.txt|dict.cc*.txt|*/dict.cc*.txt|dictcc*.txt|*/dictcc*.txt|deen*.txt|*/deen*.txt|deru*.txt|*/deru*.txt)
      return 0
      ;;
  esac
  return 1
}

while IFS= read -r path; do
  if is_forbidden_path "$path"; then
    report_forbidden_path "tracked" "$path"
  fi
done < <(git ls-files)

# dict.cc exports are large tab-delimited files. Flag unusually large tracked text
# files even if a downloaded export was renamed before being committed.
while IFS=$'\t' read -r size path; do
  if [[ "$path" == *.txt && "$size" -ge 500000 ]]; then
    echo "error: tracked text file may contain imported dictionary data ($size bytes): $path" >&2
    failed=1
  fi
done < <(
  git ls-files -z | while IFS= read -r -d '' path; do
    printf '%s\t%s\n' "$(wc -c < "$path" | tr -d ' ')" "$path"
  done
)

# A public repository exposes reachable history too, even after a later commit
# deletes a file. Inspect every historical blob as a second line of defense.
while read -r object_type size path; do
  [[ "$object_type" == "blob" && -n "${path:-}" ]] || continue
  if is_forbidden_path "$path"; then
    report_forbidden_path "historical" "$path"
  elif [[ "$path" == *.txt && "$size" -ge 500000 ]]; then
    echo "error: historical text blob may contain dictionary data ($size bytes): $path" >&2
    failed=1
  fi
done < <(
  git rev-list --objects --all |
    git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)'
)

if [[ "$failed" -ne 0 ]]; then
  echo "Local dictionary exports and databases must stay outside Git." >&2
  exit 1
fi

echo "No tracked dictionary exports or local databases found."
