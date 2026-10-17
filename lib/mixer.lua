local mixer = {}

local channels, numChannels = {}, 0

local function scanChannel()
  for i=1, numChannels do
    if not channels[i] then
      return i
    end
  end
  return 1
end

function mixer.allocateChannels(n)
  numChannels = n
end

function mixer.queueAudio(channel, audioChannels, loops)
  if #audioChannels[1] < 1 then return -1 end
  if channel == -1 then
    channel = scanChannel()
  end
  if channels[channel] or channel > numChannels then
    return -1
  end

  local channelTbl = { audioChannels = {} }
  channels[channel] = channelTbl
  for k, v in pairs(audioChannels) do
    channelTbl.audioChannels[k] = {
      offset = 1,
      audio = v,
      loops = loops
    }
  end

  return channel
end

function mixer.unqueueAudio(channel)
  channels[channel] = nil
end

local function addChannelFrames(channel, mixed, audioChannel, frames)
  -- TODO: Better approach than adding
  local auCh = channel.audioChannels[audioChannel]
  if not auCh then return true end
  for i=1, frames do
    local offset = auCh.offset
    if not auCh.audio[offset] then
      if auCh.loops ~= 0 then
        if auCh.loops > 0 then
          offset = 1
          auCh.loops = auCh.loops - 1
        end
      else
        channel.audioChannels[audioChannel] = nil
        return true
      end
    end

    mixed[i] = math.max(-128, math.min(127, (mixed[i] or 0) + auCh.audio[offset]))
    auCh.offset = auCh.offset + 1
  end
end

function mixer.mixFrames(frames)
  local mixed = {{}, {}}
  for k, v in pairs(channels) do
    local c1done = addChannelFrames(v, mixed[1], 1, frames)
    local c2done = addChannelFrames(v, mixed[2], 2, frames)
    if c1done and c2done then
      channels[k] = nil
    end
  end

  return mixed
end

return mixer