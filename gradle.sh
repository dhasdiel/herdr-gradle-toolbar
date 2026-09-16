#!/bin/sh
# Gradle Toolbar — IntelliJ-style Gradle buttons for herdr.
#
#   gradle.sh <task args...>   run a task in the shared "Gradle" output pane
#   gradle.sh --pick           task picker (runs inside the popup pane)
#   gradle.sh --open-picker    open the picker popup (the "tasks" action)
#   gradle.sh --selfcheck      sanity check, non-zero exit on failure
set -u
HERDR="${HERDR_BIN_PATH:-herdr}"

# jf <dotted.path>: print a string field from the first JSON value on stdin.
jf() {
  python3 -c 'import json, sys
d, _ = json.JSONDecoder().raw_decode(sys.stdin.read())
for k in sys.argv[1].split("."):
    d = d.get(k) if isinstance(d, dict) else None
print(d if isinstance(d, str) else "")' "$1"
}

# ctx <field>: print a top-level field of HERDR_PLUGIN_CONTEXT_JSON.
ctx() { printf '%s\n' "${HERDR_PLUGIN_CONTEXT_JSON:-{}}" | jf "$1"; }

# find_root <dir>: walk up to the nearest dir containing gradlew.
find_root() {
  d="$1"
  case "$d" in /*) ;; *) d="$PWD" ;; esac
  while [ ! -f "$d/gradlew" ]; do
    [ "$d" = / ] && return 1
    d="${d%/*}"; [ -n "$d" ] || d=/
  done
  printf '%s\n' "$d"
}

shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# output_pane <cwd>: reuse the stored output pane or split a new one.
output_pane() {
  store="${HERDR_PLUGIN_STATE_DIR:-$HOME/.cache}/gradle-pane"
  out=""
  if [ -f "$store" ]; then
    out="$(cat "$store")"
    "$HERDR" pane get "$out" >/dev/null 2>&1 || out=""
  fi
  if [ -z "$out" ]; then
    src="$(ctx focused_pane_id)"; [ -n "$src" ] || src="${HERDR_PANE_ID:-}"
    if [ -n "$src" ]; then
      out="$("$HERDR" pane split "$src" --direction down --ratio 0.35 --cwd "$1" --focus | jf result.pane.pane_id)"
    else
      out="$("$HERDR" pane split --direction down --ratio 0.35 --cwd "$1" --focus | jf result.pane.pane_id)"
    fi
    [ -n "$out" ] || { echo "could not open output pane" >&2; return 1; }
    printf '%s\n' "$out" > "$store"
  fi
  printf '%s\n' "$out"
}

run_task() {
  cwd="$(ctx focused_pane_cwd)"
  [ -n "$cwd" ] || cwd="$(ctx workspace_cwd)"
  [ -n "$cwd" ] || cwd="$PWD"
  root="$(find_root "$cwd")" || {
    echo "gradlew not found in $cwd or any parent — is this a Gradle project?" >&2
    return 1
  }
  out="$(output_pane "$root")" || return 1
  "$HERDR" pane rename "$out" "gradle: $*" >/dev/null 2>&1
  # ponytail: no busy check on the reused pane — if a build is still running,
  # the typed text lands in its stdin. Upgrade: inspect `herdr pane get`
  # foreground state and open a fresh pane when busy.
  "$HERDR" pane run "$out" "cd $(shell_quote "$root") && ./gradlew $*"
}

write_default_tasks() {
  cat <<'EOF'
# One task per line:  Label|gradle args
# Label is optional — a bare line is used as the args.
Build|build
Clean|clean
Run (JVM)|run
Generate MAVLink|generateMavlink
All tests|allTests
Check|check
Assemble debug APK|assembleDebug
Install debug APK|installDebug
iOS simulator tests|iosSimulatorArm64Test
Refresh dependencies|--refresh-dependencies build
List all tasks|tasks --all
EOF
}

pick() {
  cfg="${HERDR_PLUGIN_CONFIG_DIR:-$PWD}/tasks.txt"
  [ -f "$cfg" ] || { mkdir -p "$(dirname "$cfg")"; write_default_tasks > "$cfg"; }
  if command -v fzf >/dev/null 2>&1; then
    line="$(grep -v '^[[:space:]]*#' "$cfg" | grep . | fzf --prompt 'gradle> ' --delimiter '\|' --with-nth 1)" || return 0
  else
    i=0
    while IFS= read -r l; do
      case "$l" in '' | '#'*) continue ;; esac
      i=$((i + 1)); printf '%2d) %s\n' "$i" "${l%%|*}"
    done < "$cfg"
    printf 'task> '
    read -r n || return 0
    line="$(grep -v '^[[:space:]]*#' "$cfg" | grep . | sed -n "${n}p")"
  fi
  [ -n "$line" ] || return 0
  case "$line" in *\|*) args="${line#*|}" ;; *) args="$line" ;; esac
  # intentional word splitting: tasks.txt lines hold full arg strings
  run_task $args
}

selfcheck() {
  fail=0
  [ "$(printf '{"a":{"b":"x"}}' | jf a.b)" = x ] || { echo "FAIL jf"; fail=1; }
  t="$(mktemp -d)"; mkdir -p "$t/p/sub"; : > "$t/p/gradlew"
  [ "$(find_root "$t/p/sub")" = "$t/p" ] || { echo "FAIL find_root"; fail=1; }
  [ "$(shell_quote "a b'c")" = "'a b'\''c'" ] || { echo "FAIL shell_quote"; fail=1; }
  rm -rf "$t"
  [ "$fail" = 0 ] && echo "selfcheck ok"
  return "$fail"
}

case "${1:-}" in
  --pick) pick ;;
  --open-picker) exec "$HERDR" plugin pane open --plugin "${HERDR_PLUGIN_ID:?}" --entrypoint tasks ;;
  --selfcheck) selfcheck ;;
  "") echo "usage: gradle.sh <task args...> | --pick | --open-picker | --selfcheck" >&2; exit 2 ;;
  *) run_task "$@" ;;
esac
