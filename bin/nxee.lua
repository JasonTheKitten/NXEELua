local originalEnv = {}
for k, v in pairs(_ENV or _G) do
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
    env.localRequire = createRequire(baseDir)
    env.lwRequire = lwRequire

    local ok, err = loadfile(filePath, "t", env)
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

local moduleParser = lwRequire("lib/moduleparser")
-- TODO: Replace with internal directory
local testModule = "../../nxengine-evo-js/bin/nx.wasm"
local testModuleHandle, err = io.open(testModule, "rb")
if not testModuleHandle then error(err) end
local module, err = moduleParser.readModule(testModuleHandle)
testModuleHandle:close()
if not module then error(err) end

local wasiLib = lwRequire("lib/wasi")
local wasiFS = lwRequire("lib/wasi_fs")

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
  env = canvas
}))
local exports = vm.exports
wasi.initialize(vm)
canvas.initialize(exports.memory)

vm.profiler.disableInstructions()
vm.profiler.disable()

local time = os.time()
assert(exports.__wasm_call_ctors())
local _, err = assert(exports.init_game())
if err ~= 0 then
  print("init_game failed with code:", err);
end

print("Entering main loop")
local hadPrevMap = false

driver.runLoop(function()
  local _, isGameRunning = assert(exports.is_game_running())
  if isGameRunning == 0 then
    print("Shutting down...")
    exports.game_shutdown()
    return false
  end

  local _, shouldSwitchMap = assert(exports.should_switch_map())
  if shouldSwitchMap == 1 then
    if hadPrevMap then
      print("Exit map...")
      exports.stageboss_on_map_exit()
    end

    print("Switch map...")
    local _, mapErr = assert(exports.handle_map_switch())
    if mapErr ~= 0 then
      print("handle_map_switch failed, shutting down...")
      exports.game_shutdown()
      return false
    end
  end

  _, isGameRunning = assert(exports.is_game_running())
  if isGameRunning == 0 then
    print("Shutting down...")
    exports.game_shutdown()
    return false
  end

  assert(exports.run_tick())
  
  if not hadPrevMap then
    print(os.time() - time)
  end
  hadPrevMap = true

  return true
end, vm.profiler)