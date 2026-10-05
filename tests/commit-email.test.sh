#!/usr/bin/env bash
# Runs the exact `run:` block from commit-email.yml against throwaway git repos
# in a temp dir. Usage: bash tests/commit-email.test.sh
set -uo pipefail
WF="${1:-$(dirname "$0")/../.github/workflows/commit-email.yml}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
python3 -c "import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));print(d['jobs']['check']['steps'][1]['run'])" "$WF" > "$T/check.sh"

mk() { # dir
  git init -q "$1"; git -C "$1" -c user.email=cb@flowmatrixai.com -c user.name=base commit -q --allow-empty -m base
}
add() { # dir author-email committer-email
  GIT_AUTHOR_NAME=a GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME=c GIT_COMMITTER_EMAIL="$3" \
    git -C "$1" commit -q --allow-empty -m "c $2"
}
run() { # name dir base expect
  local base="$3" head out rc
  head=$(git -C "$2" rev-parse HEAD)
  out=$(cd "$2" && DOMAIN=flowmatrixai.com BASE="$base" HEAD="$head" bash "$T/check.sh" 2>&1); rc=$?
  if { [ "$4" = pass ] && [ $rc -eq 0 ]; } || { [ "$4" = fail ] && [ $rc -ne 0 ]; }; then
    echo "ok   - $1 (exit $rc)"
  else
    echo "FAIL - $1 (exit $rc, wanted $4)"; echo "$out"; FAILED=1
  fi
}
FAILED=0

mk "$T/a"; b=$(git -C "$T/a" rev-parse HEAD); add "$T/a" cb@flowmatrixai.com cb@flowmatrixai.com
run "work-address commit passes" "$T/a" "$b" pass

mk "$T/b"; b=$(git -C "$T/b" rev-parse HEAD); add "$T/b" someone@gmail.com someone@gmail.com
run "personal-address commit fails" "$T/b" "$b" fail

mk "$T/c"; b=$(git -C "$T/c" rev-parse HEAD); add "$T/c" cb@flowmatrixai.com someone@gmail.com
run "work author, personal committer fails" "$T/c" "$b" fail

mk "$T/d"; b=$(git -C "$T/d" rev-parse HEAD)
add "$T/d" "29139614+renovate[bot]@users.noreply.github.com" noreply@github.com
add "$T/d" "198982749+Copilot@users.noreply.github.com" "198982749+Copilot@users.noreply.github.com"
run "bot identities pass" "$T/d" "$b" pass

mk "$T/e"; git -C "$T/e" -c user.email=old@gmail.com -c user.name=o commit -q --allow-empty -m old
b=$(git -C "$T/e" rev-parse HEAD); add "$T/e" cb@flowmatrixai.com cb@flowmatrixai.com
run "existing personal history is not re-checked" "$T/e" "$b" pass

mk "$T/f"; add "$T/f" someone@gmail.com someone@gmail.com
run "new-branch push (zero base) checks HEAD" "$T/f" 0000000000000000000000000000000000000000 fail

mk "$T/g"; b=$(git -C "$T/g" rev-parse HEAD)
add "$T/g" someone@gmail.com someone@gmail.com; add "$T/g" cb@flowmatrixai.com cb@flowmatrixai.com
run "personal commit below a work HEAD in the range fails" "$T/g" "$b" fail

exit $FAILED
