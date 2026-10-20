#!/usr/bin/env bash
# Runs the exact "Scan" run: block from gitleaks.yml against throwaway git
# repos. Needs python3 with PyYAML and gitleaks on PATH.
# Usage: bash tests/gitleaks-scan.test.sh [workflow] [org-config]
#
# Token-shaped strings are assembled at runtime and never written to this file.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WF="${1:-$HERE/../.github/workflows/gitleaks.yml}"
ORG="${2:-$HERE/../.gitleaks.toml}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
python3 -c "
import yaml,sys
steps=yaml.safe_load(open(sys.argv[1]))['jobs']['scan']['steps']
print(next(s['run'] for s in steps if s.get('name')=='Scan'))" "$WF" > "$T/step.sh" || exit 1

rnd() { python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range($1)))"; }
PAT="ghp""_$(rnd 36)"

g() { git -C "$1" -c user.email=t@example.com -c user.name=t "${@:2}"; }
mk() { # dir
  git init -q -b main "$1"
  printf 'base\n' > "$1/m.md"; g "$1" add .; g "$1" commit -q -m base
  cp "$ORG" "$1/.gitleaks.toml"
}
run() { # name dir expect
  local out rc ok=1
  out=$(cd "$2" && bash --noprofile --norc -eo pipefail "$T/step.sh" 2>&1); rc=$?
  { [ "$3" = pass ] && [ $rc -eq 0 ]; } || { [ "$3" = fail ] && [ $rc -ne 0 ]; } || ok=0
  printf '%s' "$out" | grep -qF -- "${PAT#ghp_}" && { ok=0; echo "  secret value reached the log"; }
  if [ $ok = 1 ]; then echo "ok   - $1 (exit $rc)"; else echo "FAIL - $1 (exit $rc, wanted $3)"; echo "$out" | tail -15; FAILED=1; fi
}
FAILED=0

mk "$T/a"
run "a clean repo passes" "$T/a" pass

mk "$T/b"; printf 'PAT: %s\n' "$PAT" >> "$T/b/m.md"; g "$T/b" add m.md; g "$T/b" commit -q -m add
run "a token in an ordinary commit fails" "$T/b" fail

# In neither parent: only the merge's own diff shows it.
mk "$T/c"
g "$T/c" checkout -q -b side; printf 's\n' > "$T/c/s.md"; g "$T/c" add s.md; g "$T/c" commit -q -m side
g "$T/c" checkout -q main; printf 'n\n' > "$T/c/n.md"; g "$T/c" add n.md; g "$T/c" commit -q -m main
g "$T/c" merge -q --no-commit side >/dev/null 2>&1
printf 'PAT: %s\n' "$PAT" >> "$T/c/m.md"; g "$T/c" add m.md; g "$T/c" commit -q -m "evil merge"
run "a token introduced only in a merge fails" "$T/c" fail

mk "$T/d"; g "$T/d" checkout -q -b side; printf 'PAT: %s\n' "$PAT" > "$T/d/x.md"
g "$T/d" add x.md; g "$T/d" commit -q -m x; g "$T/d" checkout -q main
run "a token on a non-HEAD branch fails" "$T/d" fail

exit $FAILED
