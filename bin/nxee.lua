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

local VM = lwRequire("lib/vm")
local vm = assert(VM.createVM(module, {
  wasi_snapshot_preview1 = wasi.imports,
  env = {}
}))
wasi.initialize(vm)

print(assert(vm.exports.__wasm_call_ctors()))
print(assert(vm.exports.init_game()))