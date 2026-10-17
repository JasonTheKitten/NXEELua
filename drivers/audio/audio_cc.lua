local mixer = localRequire("lib/mixer")

local SAMPLE_RATE = 48000
local CHUNK_SAMPLES = 2048

local audioLib = {}

local memory, beforePlay
local handles = {}
local leftSpeaker, rightSpeaker

function audioLib.audio_load_buf(bufPtr, len)
  local channelLeft, channelRight = {}, {}
  for i=1, len / 2 do
    local mem1 = assert(memory.u8(bufPtr + (i - 1) * 2))
    if mem1 > 127 then mem1 = mem1 - 256 end
    local mem2 = assert(memory.u8(bufPtr + (i - 1) * 2 + 1))
    if mem2 > 127 then mem2 = mem2 - 256 end

    channelLeft[i] = mem1
    channelRight[i] = mem2
  end

  local handleId = #handles + 1
  handles[handleId] = {
    channelLeft = channelLeft,
    channelRight = channelRight
  }

  -- print("[Lua] Successfully loaded audio track #" .. handleId)

  return handleId
end

function audioLib.audio_free_buf(handleId)
  handles[handleId] = nil
end

function audioLib.audio_play_channel(channel, handleId, loops)
  local handle = handles[handleId]
  if not handle then return false end

  if channel > 0x80000000 then
    channel = channel - 0x100000000
  end
  return mixer.queueAudio(channel, { handle.channelLeft, handle.channelRight }, loops)
end

function audioLib.audio_halt_channel(channel)
  mixer.unqueueAudio(channel)
  return 0
end

function audioLib.initialize(exports)
  mixer.allocateChannels(64) -- TODO: Get this from the game
  memory = exports.memory
  beforePlay = exports.audio_request_data
end

local sampleDebt = CHUNK_SAMPLES * 2
local prevClock
local preparedAudio

function audioLib.frame()
  if preparedAudio then
    local entry = preparedAudio

    if not entry.leftAccepted then
      entry.leftAccepted = leftSpeaker.playAudio(entry.left, 3) == true
    end

    if not entry.rightAccepted then
      entry.rightAccepted = rightSpeaker.playAudio(entry.right, 3) == true
    end

    if entry.leftAccepted and entry.rightAccepted then
      preparedAudio = nil
    end
  end

  local newClock = os.clock()
  local elapsed = prevClock and math.max(0, newClock - prevClock) or 0

  sampleDebt = math.min(
    sampleDebt + elapsed * SAMPLE_RATE,
    CHUNK_SAMPLES * 2
  )
  prevClock = newClock

  if sampleDebt >= CHUNK_SAMPLES and not preparedAudio then
    if beforePlay then beforePlay(CHUNK_SAMPLES * 2) end
    local mixed = mixer.mixFrames(CHUNK_SAMPLES)
    local left, right = mixed[1] or {}, mixed[2] or {}

    preparedAudio = {
      left = left,
      right = right,
      leftAccepted = not leftSpeaker or #left == 0,
      rightAccepted = not rightSpeaker or #right == 0
    }

    sampleDebt = sampleDebt - CHUNK_SAMPLES
  end
end

function audioLib.setSpeakers(left, right)
  leftSpeaker = left
  rightSpeaker = right
end

return audioLib