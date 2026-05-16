--[[
    Smart Maniac NPC - Client-side Text-to-Speech
    Plays AI-generated phrases as actual voice audio using sound.PlayURL().
    Uses Google Translate TTS with deep pitch-shift for a rough male voice.
    The playback rate is lowered to create a menacing deep voice effect.
]]

SmartManiac = SmartManiac or {}
SmartManiac.TTS = SmartManiac.TTS or {}

local activeTTSChannels = {}

-- Voice configuration for the deep male maniac voice
local VOICE_PLAYBACK_RATE = 0.72   -- Lower = deeper voice (0.72 gives a rough deep male voice)
local VOICE_VOLUME = 1.0
local VOICE_FADE_MIN = 200
local VOICE_FADE_MAX = 1500

local function CleanupChannels()
    for npc, channels in pairs(activeTTSChannels) do
        if not IsValid(npc) then
            if istable(channels) then
                for _, ch in ipairs(channels) do
                    if IsValid(ch) then ch:Stop() end
                end
            elseif IsValid(channels) then
                channels:Stop()
            end
            activeTTSChannels[npc] = nil
        elseif istable(channels) then
            for i = #channels, 1, -1 do
                if not IsValid(channels[i]) or channels[i]:GetState() == GMOD_CHANNEL_STOPPED then
                    if IsValid(channels[i]) then channels[i]:Stop() end
                    table.remove(channels, i)
                end
            end
            if #channels == 0 then
                activeTTSChannels[npc] = nil
            end
        end
    end
end

--- URL-encode a string for use in query parameters.
local function UrlEncode(str)
    str = string.gsub(str, "([^%w _%%%-%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
    return str
end

--- Split long text into chunks for Google TTS (max ~200 chars per request).
local function SplitText(text, maxLen)
    maxLen = maxLen or 180
    if #text <= maxLen then return { text } end

    local chunks = {}
    local remaining = text

    while #remaining > 0 do
        if #remaining <= maxLen then
            table.insert(chunks, remaining)
            break
        end

        local cutPos = maxLen
        -- Try to cut at a sentence boundary
        local lastPeriod = string.find(string.sub(remaining, 1, maxLen), "%.[%s]?[^%.]*$")
        local lastComma = string.find(string.sub(remaining, 1, maxLen), ",[%s]?[^,]*$")
        local lastSpace = string.find(string.sub(remaining, 1, maxLen), "%s[^%s]*$")

        if lastPeriod and lastPeriod > maxLen * 0.3 then
            cutPos = lastPeriod
        elseif lastComma and lastComma > maxLen * 0.3 then
            cutPos = lastComma
        elseif lastSpace then
            cutPos = lastSpace
        end

        table.insert(chunks, string.Trim(string.sub(remaining, 1, cutPos)))
        remaining = string.Trim(string.sub(remaining, cutPos + 1))
    end

    return chunks
end

--- Speak a phrase as audio near an NPC using TTS with deep male voice.
-- @param npc Entity  The NPC entity to position the sound at.
-- @param phrase string  The Russian text to speak.
function SmartManiac.TTS.Speak(npc, phrase)
    if not IsValid(npc) then return end
    if not phrase or phrase == "" then return end

    -- Stop any currently playing TTS for this NPC
    SmartManiac.TTS.StopNPC(npc)

    -- Strip quotes that the AI might add
    phrase = string.gsub(phrase, '^"', "")
    phrase = string.gsub(phrase, '"$', "")
    phrase = string.Trim(phrase)

    if phrase == "" then return end

    -- Split long phrases into chunks
    local chunks = SplitText(phrase)

    activeTTSChannels[npc] = activeTTSChannels[npc] or {}

    for i, chunk in ipairs(chunks) do
        local encoded = UrlEncode(chunk)
        local ttsUrl = "https://translate.google.com/translate_tts?ie=UTF-8&tl=ru&client=tw-ob&q=" .. encoded

        -- Delay each chunk slightly for sequential playback
        timer.Simple((i - 1) * 1.5, function()
            if not IsValid(npc) then return end

            sound.PlayURL(ttsUrl, "3d mono", function(channel, errorID, errorName)
                if not IsValid(channel) then
                    print("[Smart Maniac] TTS error: " .. tostring(errorName))
                    return
                end

                if not IsValid(npc) then
                    channel:Stop()
                    return
                end

                -- Store channel for tracking
                activeTTSChannels[npc] = activeTTSChannels[npc] or {}
                table.insert(activeTTSChannels[npc], channel)

                -- Position and configure the deep male voice
                channel:SetPos(npc:GetPos() + Vector(0, 0, 60))
                channel:Set3DFadeDistance(VOICE_FADE_MIN, VOICE_FADE_MAX)
                channel:SetVolume(VOICE_VOLUME)
                channel:SetPlaybackRate(VOICE_PLAYBACK_RATE)
                channel:Play()
            end)
        end)
    end
end

--- Stop all TTS playback for an NPC.
function SmartManiac.TTS.StopNPC(npc)
    if not activeTTSChannels[npc] then return end

    if istable(activeTTSChannels[npc]) then
        for _, ch in ipairs(activeTTSChannels[npc]) do
            if IsValid(ch) then ch:Stop() end
        end
    elseif IsValid(activeTTSChannels[npc]) then
        activeTTSChannels[npc]:Stop()
    end

    activeTTSChannels[npc] = nil
end

--- Check if an NPC is currently speaking.
function SmartManiac.TTS.IsSpeaking(npc)
    if not activeTTSChannels[npc] then return false end

    if istable(activeTTSChannels[npc]) then
        for _, ch in ipairs(activeTTSChannels[npc]) do
            if IsValid(ch) and ch:GetState() == GMOD_CHANNEL_PLAYING then
                return true
            end
        end
    end

    return false
end

-- Update 3D positions of active TTS channels to follow NPCs
hook.Add("Think", "SmartManiac_TTS_Update", function()
    for npc, channels in pairs(activeTTSChannels) do
        if not IsValid(npc) then
            if istable(channels) then
                for _, ch in ipairs(channels) do
                    if IsValid(ch) then ch:Stop() end
                end
            end
            activeTTSChannels[npc] = nil
        elseif istable(channels) then
            local pos = npc:GetPos() + Vector(0, 0, 60)
            for _, ch in ipairs(channels) do
                if IsValid(ch) then
                    ch:SetPos(pos)
                end
            end
        end
    end
end)

-- Periodic cleanup
timer.Create("SmartManiac_TTS_Cleanup", 5, 0, CleanupChannels)

print("[Smart Maniac] Client TTS module loaded (deep male voice).")
