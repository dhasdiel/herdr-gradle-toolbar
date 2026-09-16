#!/bin/sh
# Gradle Toolbar — IntelliJ-style Gradle buttons for herdr.
#
#   gradle.sh <task args...>   run a task in the shared "Gradle" output pane
#   gradle.sh --pick           task picker (runs inside the popup pane)
#   gradle.sh --open-picker    open the picker popup (the "tasks" action)
#   gradle.sh --rerun          rerun the last task
#   gradle.sh --stop           ctrl+c the output pane
#   gradle.sh --selfcheck      sanity check, non-zero exit on failure
set -u
HERDR="${HERDR_BIN_PATH:-herdr}"

state_dir() { printf '%s' "${HERDR_PLUGIN_STATE_DIR:-$HOME/.cache}"; }

# jf <dotted.path>: print a scalar field from the first JSON value on stdin.
jf() {
  python3 -c 'import json, sys
d, _ = json.JSONDecoder().raw_decode(sys.stdin.read())
for k in sys.argv[1].split("."):
    d = d.get(k) if isinstance(d, dict) else None
if isinstance(d, bool): print(str(d).lower())
elif isinstance(d, (int, float, str)): print(d)
else: print()' "$1"
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

# pane_busy <pane_id>: true when the pane is not at an interactive prompt.
pane_busy() {
  [ "$("$HERDR" pane get "$1" 2>/dev/null | jf result.pane.interactive_ready)" = "false" ]
}

# output_pane <cwd>: reuse the stored output pane or split a new one.
output_pane() {
  store="$(state_dir)/gradle-pane"
  out=""
  if [ -f "$store" ]; then
    out="$(cat "$store")"
    "$HERDR" pane get "$out" >/dev/null 2>&1 || out=""
    # a running build owns the pane — open a fresh one this time
    [ -n "$out" ] && pane_busy "$out" && out=""
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
  printf '%s' "$*" > "$(state_dir)/last-task"
  label="gradle: $*"
  "$HERDR" pane rename "$out" "$label" >/dev/null 2>&1
  # wrap the run so the pane title flips to ✓/✗ and a notification fires
  hb="$(shell_quote "$HERDR")"
  ok="$hb pane rename $out $(shell_quote "$label ✓") >/dev/null 2>&1; $hb notification show Gradle --body $(shell_quote "$* finished") --sound done >/dev/null 2>&1"
  bad="$hb pane rename $out $(shell_quote "$label ✗") >/dev/null 2>&1; $hb notification show Gradle --body $(shell_quote "$* failed") --sound request >/dev/null 2>&1"
  "$HERDR" pane run "$out" "cd $(shell_quote "$root") && ./gradlew $* && { $ok; } || { $bad; }"
}

rerun() {
  f="$(state_dir)/last-task"
  [ -f "$f" ] || { echo "no previous task to rerun" >&2; return 1; }
  # intentional word splitting: last-task holds a full arg string
  run_task $(cat "$f")
}

stop() {
  p="$(cat "$(state_dir)/gradle-pane" 2>/dev/null || true)"
  [ -n "$p" ] || { echo "no gradle output pane" >&2; return 1; }
  "$HERDR" pane send-keys "$p" ctrl+c
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

# task_file: repo-local .herdr-gradle-tasks wins over the global config file.
task_file() {
  c="$(ctx focused_pane_cwd)"; [ -n "$c" ] || c="$(ctx workspace_cwd)"; [ -n "$c" ] || c="$PWD"
  r="$(find_root "$c" 2>/dev/null || true)"
  if [ -n "$r" ] && [ -f "$r/.herdr-gradle-tasks" ]; then
    printf '%s' "$r/.herdr-gradle-tasks"
  else
    printf '%s' "${HERDR_PLUGIN_CONFIG_DIR:-$PWD}/tasks.txt"
  fi
}

pick() {
  cfg="$(task_file)"
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
  [ "$(printf '{"a":{"b":"x","c":false}}' | jf a.b)" = x ] || { echo "FAIL jf str"; fail=1; }
  [ "$(printf '{"a":false}' | jf a)" = false ] || { echo "FAIL jf bool"; fail=1; }
  t="$(mktemp -d)"; mkdir -p "$t/p/sub"; : > "$t/p/gradlew"
  [ "$(find_root "$t/p/sub")" = "$t/p" ] || { echo "FAIL find_root"; fail=1; }
  [ "$(shell_quote "a b'c")" = "'a b'\''c'" ] || { echo "FAIL shell_quote"; fail=1; }
  echo "x|y" > "$t/p/.herdr-gradle-tasks"
  got="$(HERDR_PLUGIN_CONTEXT_JSON="{\"focused_pane_cwd\":\"$t/p/sub\"}" HERDR_PLUGIN_CONFIG_DIR=/nonexistent task_file)"
  [ "$got" = "$t/p/.herdr-gradle-tasks" ] || { echo "FAIL task_file project: $got"; fail=1; }
  got="$(HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_cwd":"/nonexistent"}' HERDR_PLUGIN_CONFIG_DIR=/cfg task_file)"
  [ "$got" = /cfg/tasks.txt ] || { echo "FAIL task_file fallback: $got"; fail=1; }
  rm -rf "$t"
  [ "$fail" = 0 ] && echo "selfcheck ok"
  return "$fail"
}

case "${1:-}" in
  --pick) pick ;;
  --open-picker) exec "$HERDR" plugin pane open --plugin "${HERDR_PLUGIN_ID:?}" --entrypoint tasks ;;
  --rerun) rerun ;;
  --stop) stop ;;
  --selfcheck) selfcheck ;;
  "") echo "usage: gradle.sh <task args...> | --pick | --open-picker | --selfcheck" >&2; exit 2 ;;
  *) run_task "$@" ;;
esac
