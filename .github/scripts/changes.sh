#!/usr/bin/env bash
# Whether a workflow's work should run: false only for a push or a pull
# request whose every changed file matches a pattern in no-ci.txt and none of
# ALWAYS. Prints ci=true or ci=false, for $GITHUB_OUTPUT. Needs history back
# to <before> (checkout's fetch-depth: 0).
# usage: changes.sh <event name> <before sha> <after sha>
#   push:          the push's two ends
#   pull_request:  the base and the head; compared from their merge base
set -euo pipefail
EVENT=$1
BEFORE=${2:-}
AFTER=$3

# what goes into a devkit or decides how it is built: always builds, whatever
# no-ci.txt says (a submodule shows as its path)
ALWAYS=(devkit.json .gitmodules .gitattributes no-ci.txt llvm-project qbe 'scripts/*' 'smoke/*'
  .github/workflows/ci.yml '.github/scripts/*')

# runs by hand or on a schedule, a new branch, or a force push past history
if { [ "$EVENT" != push ] && [ "$EVENT" != pull_request ]; } || [ -z "$BEFORE" ] \
    || [ "$BEFORE" = 0000000000000000000000000000000000000000 ] \
    || ! git cat-file -e "$BEFORE^{commit}" || ! git cat-file -e "$AFTER^{commit}"; then
  echo ci=true
  exit 0
fi

# a pull request's own changes, not what its base gained since it branched
RANGE=("$BEFORE" "$AFTER")
[ "$EVENT" = pull_request ] && RANGE=("$BEFORE...$AFTER")

matches () { # <file> <pattern>...
  local f=$1 p
  shift
  for p in "$@"; do
    # shellcheck disable=SC2053 # a glob on purpose
    [[ $f == $p ]] && return 0
  done
  return 1
}

mapfile -t patterns < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' no-ci.txt | grep -v '^$')
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if matches "$f" "${ALWAYS[@]}" || ! matches "$f" "${patterns[@]}"; then
    echo "changed: $f" >&2
    echo ci=true
    exit 0
  fi
done < <(git diff --name-only "${RANGE[@]}")
echo "only files of no-ci.txt changed; skipping" >&2
echo ci=false
