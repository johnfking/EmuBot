# EmuBot Lua Utilities

This repository contains Lua helpers for working with MacroQuest's EmuBot.

## Prerequisites

The code and tests are written in plain Lua. Any Lua 5.2+ interpreter or
LuaJIT should work. On developer machines you can install Lua with:

- **Debian/Ubuntu:** `sudo apt-get install lua5.4`
- **macOS (Homebrew):** `brew install lua`
- **Windows (Chocolatey):** `choco install lua`

If you already have a Lua interpreter installed under a different name, you can
point the test runner at it by setting the `LUA_INTERPRETER` environment
variable.

## Running tests

Use the provided helper script to execute the repository's unit tests:

```bash
./scripts/run-tests.sh
```

The script will search for a Lua interpreter (`lua`, `lua5.4`, `lua5.3`,
`lua5.2`, or `luajit`). If no interpreter is found it will exit with
instructions for installing one.

You can also pass additional arguments through to the Lua interpreter. For
example, to enable Lua's built-in JIT compiler when using LuaJIT:

```bash
LUA_INTERPRETER=luajit ./scripts/run-tests.sh -j on
```

## Formatting and linting

No automated formatting or linting tools are currently configured for this
project. Please follow the existing code style when making changes.
