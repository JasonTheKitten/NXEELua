# NXEELua

NXEELua is a project that allows for running a port of NXEngine-Evo in Lua.

In order to achieve this, three repositories come into play:

* [luwasm](https://github.com/JasonTheKitten/luwasm) - A WebAssembly VM running in Lua. The VM was specifically made to run this project (and has not been tested against other programs.
* [NXEELua](https://github.com/JasonTheKitten/NXEELua) - Binds luwasm functions used by the port for graphics and audio, and executes the main game loop.
* [NXEngine-Evo WASM Port](https://github.com/JasonTheKitten/nxengine-evo-wasm) - This repository ports NXEngine-Evo to run in WebAssembly, stubs a number of SDL functions, and exports
functions that can be passed to the WASM VM to handle graphics and audio rendering.

This repository runs the main game loop, and provides audio and graphics binding.

On LuaJIT and PUC Lua 5.5, graphics are handled by luasdl2 and audio is a stub. Please ensure you have `luasdl2` and `luafilesystem` installed via LuaRocks.

On CraftOS-PC and CraftOS-PC: Accelerated, graphics and audio are handled via periphemu, and no additional configuration needs done. Audio mixing is done via `lib/mixer.lua`, and framebuffering is done via `lib/virtcanv.lua`.

It is recommended you run in either CraftOS-PC: Accelerated or LuaJIT (as opposed to their slower predecessors).

The luwasm and nxeelua folders should be sibling directories. You should also put assets from the official game in `nxeelua/data/data`

Example layout:
```
- /luwasm - Wasm VM
- /nxeelua - NXEELua repo
| - /data - New folder
    | - /data - Assets extracted from the game. See the nxengine-evo wiki to learn how to extract assets.
```