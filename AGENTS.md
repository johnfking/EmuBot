# Repository Instructions

## Tooling
To run the Lua test suite locally inside the container, install Lua 5.4, `luac`, and Busted via:

```bash
sudo apt-get update
sudo apt-get install -y lua5.4 lua5.4-dev luarocks
sudo luarocks install busted
```

The `lua5.4` Debian package provides the `luac` binary required for bytecode checks, while `luarocks` supplies the `busted` test runner.

## Testing
Run the test suite with:

```bash
busted
```

Use `luac -p <file.lua>` to syntax-check individual Lua files when needed.
