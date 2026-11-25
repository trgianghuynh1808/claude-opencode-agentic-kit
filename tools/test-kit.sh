#!/usr/bin/env bash
# Hồi quy cho lệnh `kit`: chạy trong thư mục tạm, với `gh` và `claude` giả, registry riêng, không bật phòng thật.
#   tools/test-kit.sh
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/projects" "$T/remote"
cat > "$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$KT/gh.log"
case "$1 $2" in
  "auth status") exit 0 ;;
  "api user") echo tester; exit 0 ;;
  "repo create") git init -q --bare "$KT/remote/$3.git"; git remote add origin "$KT/remote/$3.git"; git push -q -u origin main; exit 0 ;;
esac
STUB
cat > "$T/bin/claude" <<'STUB'
#!/usr/bin/env bash
sed -i.bak 's/TODO: what the app is, who uses it, main stack./Drafted by the stub./' AGENTS.md; rm -f AGENTS.md.bak
STUB
chmod +x "$T/bin/gh" "$T/bin/claude"
export KT="$T" KIT_PROJECTS_DIR="$T/projects" AGENT_ROOMS_FILE="$T/rooms.json" PATH="$T/bin:$PATH"
fail=0
check() { if eval "$2"; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
gitinit() { git init -q -b main "$1" && git -C "$1" config user.email t@t && git -C "$1" config user.name t; }
K() { "$KIT/kit" "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
says() { local want="$1" out; shift; out="$(K "$@")"; grep -q "$want" <<<"$out"; }   # grep -q on a pipe would SIGPIPE the writer under pipefail

echo "kit new (local):"
K new demo-app --port 4010 --topic 21 --no-start --yes --no-github >/dev/null
P="$T/projects/demo-app"
check "creates a git repo with 2 commits"      '[[ "$(git -C "$P" rev-list --count HEAD)" == 2 ]]'
check "working tree is clean"                  '[[ -z "$(git -C "$P" status --porcelain)" ]]'
check "room.env has topic and port"            'grep -q "TELEGRAM_TOPIC_ID=\"21\"" "$P/.agents/room.env" && grep -q "APP_PORT=\"4010\"" "$P/.agents/room.env"'
check "room registered for the bridge"         'grep -q "\"topicId\": 21" "$T/rooms.json"'
check "no remote when --no-github"             '[[ -z "$(git -C "$P" remote)" ]]'

echo "kit new (GitHub, stubbed):"
K new demo-two --port 4011 --topic 22 --no-start --yes >/dev/null
check "GitHub repo is public by default"       'grep -q "repo create demo-two --public" "$T/gh.log"'
check "main is pushed to origin"               '[[ "$(git -C "$T/projects/demo-two" rev-list --count origin/main)" -ge 1 ]]'
K new demo-three --port 4012 --topic 23 --no-start --yes --private >/dev/null
check "--private creates a private repo"       'grep -q "repo create demo-three --private" "$T/gh.log"'

echo "kit add (existing repo, own CLAUDE.md, --agents):"
E="$T/existing"; gitinit "$E"; echo '{"devDependencies":{"vite":"5"}}' > "$E/package.json"; echo CLAUDE_EXISTING_RULES > "$E/CLAUDE.md"
git -C "$E" add -A && git -C "$E" commit -qm init
K add "$E" --topic 24 --port 5173 --no-start --yes --agents >/dev/null
check "keeps the project's own CLAUDE.md text" 'grep -q CLAUDE_EXISTING_RULES "$E/CLAUDE.md"'
check "adds the AUTO_MODE section"             'grep -q "^## AUTO_MODE" "$E/CLAUDE.md"'
check "AGENTS.md draft is its own commit"      '[[ "$(git -C "$E" log -1 --format=%s)" == docs:* ]]'
check "tree is clean"                          '[[ -z "$(git -C "$E" status --porcelain)" ]]'

echo "kit add (refusals):"
D="$T/dirty"; gitinit "$D"; echo a > "$D/a"; git -C "$D" add -A; git -C "$D" commit -qm i; echo b >> "$D/a"
check "dirty tree is refused"                  'says "chưa commit" add "$D" --topic 30 --port 4000 --no-start --yes'
mkdir -p "$T/plain"
check "non-git folder is refused"              'says "không phải git repo" add "$T/plain" --topic 31 --port 4000 --no-start --yes'
check "existing room is refused"               'says "đã là một phòng" add "$E" --topic 32 --port 4001 --no-start --yes'
O="$T/other"; gitinit "$O"; echo a > "$O/a"; git -C "$O" add -A; git -C "$O" commit -qm i
check "topic used by another room is refused"  'says "đã thuộc về" add "$O" --topic 21 --port 4002 --no-start --yes'
check "missing topic without a terminal fails" 'says "Thiếu hoặc sai Topic" add "$O" --port 4002 --no-start --yes </dev/null'
check "non-empty target for new is refused"    'says "không rỗng" new demo-app --port 4020 --topic 40 --no-start --yes --no-github'
check "GitHub without --yes/tty asks first and creates nothing" '! K new needs-confirm --port 4030 --topic 41 --no-start </dev/null >/dev/null; [[ ! -d "$T/projects/needs-confirm" ]]'

echo "kit upgrade / status / remove:"
echo "# drift" >> "$P/scripts/room-ops.py"; git -C "$P" add -A; git -C "$P" commit -qm drift
sed -i.bak 's/^AUTO_MODE=.*/AUTO_MODE="true"/' "$T/projects/demo-two/.agents/room.env"; rm -f "$T/projects/demo-two/.agents/room.env.bak"
echo dirty >> "$T/projects/demo-three/README.md"
OUT="$(K upgrade --no-bridge)"
check "idle room is upgraded and committed"    'grep -q "update kit" <<<"$(git -C "$P" log -1 --format=%s)" && ! grep -q "# drift" "$P/scripts/room-ops.py"'
check "busy room (AUTO_MODE on) is skipped"    'grep -q "đang bận" <<<"$OUT"'
check "dirty room is skipped"                  'grep -q "cây git đang dơ" <<<"$OUT"'
check "status lists every room"                'out="$(K status --no-bridge)"; [[ "$(grep -c "^demo-\|^existing" <<<"$out")" == 4 ]]'
K remove demo-app --yes >/dev/null
check "remove drops it from the registry"      '! grep -q "\"demo-app\"" "$T/rooms.json"'
check "remove keeps the project files"         '[[ -d "$P/scripts" ]]'

[[ $fail == 0 ]] && echo "OK" || { echo "FAILED"; exit 1; }
