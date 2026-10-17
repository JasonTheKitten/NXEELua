local originalEnv = {}
for k, v in pairs(_G) do
  originalEnv[k] = v
end

local scriptPath, scriptDir
if originalEnv.PROGRAM_LOCATION then
  scriptDir = originalEnv.PROGRAM_LOCATION
else
  scriptPath = debug.getinfo(1, "S").source:sub(2)
  scriptDir = (scriptPath:match("(.*/)") or "./") .. "../"
end

local cache = {}
local lwRequire

local function createRequire(baseDir)
  return function(name)
    local loadName = name
    if loadName == "driver" then
      if originalEnv.DRIVER_NAME then
        loadName = "drivers/" .. originalEnv.DRIVER_NAME
      elseif term and term.setGraphicsMode then
        loadName = "drivers/driver_ccpc"
      else
        loadName = "drivers/driver_puc"
      end
    end

    local filePath = baseDir .. loadName .. ".lua"
    if cache[filePath] then
      return cache[filePath]
    end

    local env = {}
    for k, v in pairs(originalEnv) do
      env[k] = v
    end
    env.loadfile = term and function(a, _, c) return loadfile(a, c) end or loadfile
    ---@diagnostic disable-next-line: undefined-global
    env.shell = shell
    env.localRequire = createRequire(baseDir)
    env.lwRequire = lwRequire

    local ok, err = env.loadfile(filePath, "t", env)
    if not ok then
      error(err)
    end

    local result = ok()
    cache[filePath] = result
    return result
  end
end

local localRequire = createRequire(scriptDir)
lwRequire = createRequire(scriptDir .. "../luwasm/")

--

_G.load = load

local wasiLib = lwRequire("lib/wasi")
local wasiFS = lwRequire("lib/wasi_fs")

local moduleParser = lwRequire("lib/moduleparser")
-- TODO: Replace with internal directory
local testModule = wasiFS.relPath("../../nxengine-evo-js/bin/nx.wasm")
local testModuleHandle, err = io.open(testModule, "rb")
if not testModuleHandle then error(err) end
local module, err = moduleParser.readModule(testModuleHandle)
testModuleHandle:close()
if not module then error(err) end

local env = {}
local fds = {
  wasiFS.createFile(wasiFS.bytesFile({})),
  wasiFS.createFile(wasiFS.logFile(function(msg)
    print("[STDOUT] " .. msg)
  end)),
  wasiFS.createFile(wasiFS.logFile(function(msg)
    print("[STDERR] " .. msg)
  end)),
  wasiFS.createPreOpenDirectory(".", wasiFS.realDir(wasiFS.relPath("../data")))
}
local wasi = wasiLib.create(env, fds)

local driver = localRequire("driver")
local canvas = localRequire("lib/canvlib").env

local VM = lwRequire("lib/vm")
local vm = assert(VM.createVM(module, {
  wasi_snapshot_preview1 = wasi.imports,
  env = canvas,
  audio = driver.audio
}))
local exports = vm.exports
wasi.initialize(vm)
canvas.initialize(exports.memory)
driver.audio.initialize(exports)

vm.profiler.disableInstructions()
vm.profiler.disable()

---@diagnostic disable-next-line: undefined-global
local periphemu, peripheral = periphemu, peripheral
if periphemu then
  periphemu.create("left", "speaker")
  periphemu.create("right", "speaker")
end
if peripheral then
  local left = peripheral.wrap("left")
  local right = peripheral.wrap("right")
  if left and left.setPosition then left.setPosition(-10, 0, 0) end
  if right and right.setPosition then right.setPosition(10, 0, 0) end
  driver.audio.setSpeakers(left, right)
end

_G.__drawTextureTime = 0
local time = term and os.clock() or os.time()
assert(exports.__wasm_call_ctors())
local _, err = assert(exports.init_game())
if err ~= 0 then
  print("[Lua] init_game failed with code:", err);
  return
end

print("[Lua] Entering main loop")
local hadPrevMap = false

driver.runLoop(function()
  local _, isGameRunning = assert(exports.is_game_running())
  if isGameRunning == 0 then
    print("[Lua] Shutting down...")
    exports.game_shutdown()
    return false
  end

  local _, shouldSwitchMap = assert(exports.should_switch_map())
  if shouldSwitchMap == 1 then
    if hadPrevMap then
      print("[Lua] Exit map...")
      exports.stageboss_on_map_exit()
    end

    print("[Lua] Switch map...")
    local _, mapErr = assert(exports.handle_map_switch())
    if mapErr ~= 0 then
      print("[Lua] handle_map_switch failed, shutting down...")
      exports.game_shutdown()
      return false
    end
  end

  _, isGameRunning = assert(exports.is_game_running())
  if isGameRunning == 0 then
    print("[Lua] Shutting down...")
    exports.game_shutdown()
    return false
  end

  assert(exports.run_tick())
  
  if not hadPrevMap then
    local ellapsedStart = (term and os.clock() or os.time()) - time
    ---@diagnostic disable-next-line: undefined-global
    print("[Lua] TIME", ellapsedStart)
  end
  hadPrevMap = true

  return true
end, vm.profiler)