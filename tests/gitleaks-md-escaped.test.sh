#!/usr/bin/env bash
# Runs the exact "Scan markdown-escaped lines" run: block from gitleaks.yml
# against throwaway git repos, under the shell GitHub uses for `run:`.
# Needs python3 with PyYAML and gitleaks on PATH.
# Usage: bash tests/gitleaks-md-escaped.test.sh [workflow] [org-config]
#
# Token-shaped strings are assembled at runtime and never written to this file:
# the stdin pass cannot apply the org [allowlist] paths, so a literal escaped
# token in tests/ would fail this repo's own scan.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WF="${1:-$HERE/../.github/workflows/gitleaks.yml}"
ORG="${2:-$HERE/../.gitleaks.toml}"
T="$(mktemp -d)"
[ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT; [ -n "${KEEP:-}" ] && echo "T=$T"
python3 -c "
import yaml,sys
steps=yaml.safe_load(open(sys.argv[1]))['jobs']['scan']['steps']
print(next(s['run'] for s in steps if s.get('name')=='Scan markdown-escaped lines'))" "$WF" > "$T/step.sh" || exit 1

rnd() { python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range($1)))"; }
PAT="ghp""_$(rnd 36)"          # plain; gitleaks git already catches this
ESC="${PAT/_/\\_}"             # what a Drive markdown export writes

mk() { # dir
  git init -q -b main "$1"
  git -C "$1" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m base
  cp "$ORG" "$1/.gitleaks.org.toml"
}
put() { # dir path content
  mkdir -p "$(dirname "$1/$2")"; printf '%b' "$3" > "$1/$2"
  git -C "$1" add -- "$2"; git -C "$1" -c user.email=t@example.com -c user.name=t commit -q -m "add $2"
}
run() { # name dir expect [grep-for-in-output]
  local out rc
  [ -f "$2/.gitleaks.toml" ] || cp "$2/.gitleaks.org.toml" "$2/.gitleaks.toml"
  out=$(cd "$2" && LC_ALL=C.UTF-8 RUNNER_TEMP="$(mktemp -d -p "$T")" bash --noprofile --norc -eo pipefail "$T/step.sh" 2>&1); rc=$?
  local ok=1
  { [ "$3" = pass ] && [ $rc -eq 0 ]; } || { [ "$3" = fail ] && [ $rc -ne 0 ]; } || ok=0
  [ -n "${4:-}" ] && ! printf '%s' "$out" | grep -qF -- "$4" && ok=0
  printf '%s' "$out" | grep -qF -- "${PAT#ghp_}" && { ok=0; echo "  secret value reached the log"; }
  if [ $ok = 1 ]; then echo "ok   - $1 (exit $rc)"; else echo "FAIL - $1 (exit $rc, wanted $3${4:+, output naming '$4'})"; echo "$out" | tail -15; FAILED=1; fi
}
FAILED=0

mk "$T/a"; put "$T/a" README.md 'nothing escaped here\n'
run "no escaped lines at all passes (grep exit 1 tolerated)" "$T/a" pass

mk "$T/b"; put "$T/b" README.md 'a\\_b and \\*c\\*\n'
run "escapes without a secret pass" "$T/b" pass

mk "$T/c"; put "$T/c" "docs/sub dir/notes.md" "PAT: $ESC\n"
run "escaped token fails and names the file" "$T/c" fail "docs/sub dir/notes.md"

mk "$T/d"; put "$T/d" notes.md "caf\xe9 PAT: $ESC\n"
run "escaped token on a non-UTF-8 line fails" "$T/d" fail notes.md

# One commit, so the diff order is fixed by path: data.txt (NUL past git's
# 8000-byte binary probe, so it diffs as text) streams before late.md.
mk "$T/e"; printf 'PAT: %s\n' "$ESC" > "$T/e/late.md"
python3 -c "import sys;open(sys.argv[1],'wb').write(b'x\\\\_y\n'*2000+b'nul\x00here\n')" "$T/e/data.txt"
git -C "$T/e" add .; git -C "$T/e" -c user.email=t@example.com -c user.name=t commit -q -m nul
run "a NUL earlier in the stream does not hide a later token" "$T/e" fail late.md

mk "$T/f"; git -C "$T/f" checkout -q -b side; put "$T/f" side.md "PAT: $ESC\n"; git -C "$T/f" checkout -q main
run "escaped token on a non-HEAD branch fails" "$T/f" fail side.md

mk "$T/g"; put "$T/g" gone.md "PAT: $ESC\n"; git -C "$T/g" rm -q gone.md
git -C "$T/g" -c user.email=t@example.com -c user.name=t commit -q -m rm
run "escaped token deleted from HEAD still fails" "$T/g" fail gone.md

mk "$T/h"; printf '[extend]\npath = ".gitleaks.org.toml"\n' > "$T/h/.gitleaks.toml"
put "$T/h" notes.md "PAT: $ESC\n"
run "repo-local config extending the org config still detects" "$T/h" fail notes.md

mk "$T/i"; printf 'not toml [[[\n' > "$T/i/.gitleaks.toml"; put "$T/i" notes.md 'a\\_b\n'
run "an unloadable config fails closed" "$T/i" fail

# Escapes outside the original class: Drive writes `\=` and `\:` too.
KEY="$(rnd 32)"
# `\=` must be the line's only escape, or a narrower prefilter still passes it.
mk "$T/j"; put "$T/j" cfg.md "password \\= $KEY\n"
run "escaped assignment (\\=) with a generic secret fails" "$T/j" fail cfg.md

mk "$T/k"; put "$T/k" notes.md "PAT: ${PAT/_/\\\\\\\\_}\n"
run "double-escaped token fails" "$T/k" fail notes.md

# A token introduced only by a merge resolution, in neither parent.
mk "$T/l"; put "$T/l" m.md 'base\n'
git -C "$T/l" checkout -q -b side; put "$T/l" s.md 'side\n'; git -C "$T/l" checkout -q main
put "$T/l" n.md 'main\n'
git -C "$T/l" -c user.email=t@example.com -c user.name=t merge -q --no-commit side >/dev/null 2>&1
printf "PAT: %s\n" "$ESC" >> "$T/l/m.md"; git -C "$T/l" add m.md
git -C "$T/l" -c user.email=t@example.com -c user.name=t commit -q -m "evil merge"
run "escaped token introduced only in a merge fails" "$T/l" fail m.md

mk "$T/m"; printf ':github-pat:1\n' > "$T/m/.gitleaksignore"; put "$T/m" README.md 'clean\n'
run "a stdin-style .gitleaksignore entry is refused" "$T/m" fail "stdin-style"

exit $FAILED
