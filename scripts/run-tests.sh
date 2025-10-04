#!/usr/bin/env bash
set -euo pipefail

candidates=()
if [[ -n "${LUA_INTERPRETER:-}" ]]; then
  candidates+=("$LUA_INTERPRETER")
fi
candidates+=("lua" "lua5.4" "lua5.3" "lua5.2" "luajit")

lua_cmd=""
for candidate in "${candidates[@]}"; do
  if command -v "$candidate" >/dev/null 2>&1; then
    lua_cmd="$candidate"
    break
  fi
done

if [[ -z "$lua_cmd" ]]; then
  cat <<'ERR' >&2
Error: no Lua interpreter found on PATH.

Install a Lua interpreter (for example `apt-get install lua5.4` on Debian/Ubuntu
or `brew install lua` on macOS) or set the LUA_INTERPRETER environment variable
before running this script.
ERR
  exit 1
fi

printf '[tests] using Lua interpreter: %s\n' "$lua_cmd"
exec "$lua_cmd" tests/test_spell_enums.lua "$@"
