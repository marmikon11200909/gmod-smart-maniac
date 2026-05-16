--[[
    Smart Maniac NPC - Client-side Text-to-Speech
    Plays AI-generated phrases as actual voice audio using sound.PlayURL().
    Uses Google Translate TTS as a free, region-independent voice source.
]]

SmartManiac = SmartManiac or {}
SmartManiac.TTS = SmartManiac.TTS or {}

local activeTTSChannels = {}

local function CleanupChannels()
    for npc, channel in pairs(activeTTSChannels) do
        if not IsValid(npc) or (IsValid(channel) and channel:GetState() == GMOD_CHANNEL_STOPPED) then
            if IsValid(channel) then
                channel:Stop()
            end
            activeTTSChannels[npc] = nil
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

--- Speak a phrase as audio near an NPC using TTS.
-- @param npc Entity  The NPC entity to position the sound at.
-- @param phrase string  The Russian text to speak.
function SmartManiac.TTS.Speak(npc, phrase)
    if not IsValid(npc) then return end
    if not phrase or phrase == "" then return end

    -- Stop any currently playing TTS for this NPC
    if activeTTSChannels[npc] and IsValid(activeTTSChannels[npc]) then
        activeTTSChannels[npc]:Stop()
        activeTTSChannels[npc] = nil
    end

    -- Strip quotes that the AI might add
    phrase = string.gsub(phrase, '^"', "")
    phrase = string.gsub(phrase, '"$', "")
    phrase = string.Trim(phrase)

    if phrase == "" then return end

    local encoded = UrlEncode(phrase)
    local ttsUrl = "https://translate.google.com/translate_tts?ie=UTF-8&tl=ru&client=tw-ob&q=" .. encoded

    sound.PlayURL(ttsUrl, "3d mono", function(channel, errorID, errorName)
        if not IsValid(channel) then
            print("[Smart Maniac] TTS error: " .. tostring(errorName))
            return
        end

        if not IsValid(npc) then
            channel:Stop()
            return
        end

        activeTTSChannels[npc] = channel

        channel:SetPos(npc:GetPos() + Vector(0, 0, 60))
        channel:Set3DFadeDistance(200, 1500)
        channel:SetVolume(1.0)
        channel:SetPlaybackRate(0.82)
        channel:Play()
    end)
end

-- Update 3D positions of active TTS channels to follow NPCs
hook.Add("Think", "SmartManiac_TTS_Update", function()
    for npc, channel in pairs(activeTTSChannels) do
        if not IsValid(npc) or not IsValid(channel) then
            if IsValid(channel) then channel:Stop() end
            activeTTSChannels[npc] = nil
        else
            channel:SetPos(npc:GetPos() + Vector(0, 0, 60))
        end
    end
end)

-- Periodic cleanup
timer.Create("SmartManiac_TTS_Cleanup", 5, 0, CleanupChannels)

print("[Smart Maniac] Client TTS module loaded.")
