// Real Lua 5.1 (the version WoW runs), compiled to WebAssembly.
import wasmoon from "wasmoon-lua5.1";

export function createLua() {
    return wasmoon.Lua.create();
}
