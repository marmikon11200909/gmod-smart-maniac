--[[
    Smart Maniac NPC - Client-side Text-to-Speech
    Uses DHTML SpeechSynthesis API for natural deep male voice.
    Falls back to Google Translate TTS if SpeechSynthesis unavailable.
    Volume adjusts based on distance to NPC for spatial audio effect.
]]

SmartManiac = SmartManiac or {}
SmartManiac.TTS = SmartManiac.TTS or {}

local ttsPanel = nil
local ttsReady = false
local ttsMethod = "none"
local activeTTSChannels = {}
local isSpeaking = false
local currentSpeakingNPC = nil

-- Voice settings
local VOICE_PITCH = 0.4
local VOICE_RATE = 0.85
local VOICE_VOLUME = 1.0
local VOICE_FADE_MIN = 200
local VOICE_FADE_MAX = 1500

-- Google TTS fallback settings
local GTTS_PLAYBACK_RATE = 0.55

--- URL-encode a string for use in query parameters.
local function UrlEncode(str)
    str = string.gsub(str, "([^%w _%%%-%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
    return str
end

--- Split long text into chunks (max ~180 chars per chunk).
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

--- Initialize the TTS DHTML panel for SpeechSynthesis.
local function InitTTSPanel()
    if IsValid(ttsPanel) then
        ttsPanel:Remove()
    end

    ttsPanel = vgui.Create("DHTML")
    ttsPanel:SetSize(1, 1)
    ttsPanel:SetPos(0, 0)
    ttsPanel:SetVisible(false)
    ttsPanel:SetAlpha(0)

    ttsPanel:AddFunction("gmod", "ttsReady", function(method)
        ttsReady = true
        ttsMethod = method or "speechsynthesis"
        print("[Smart Maniac] TTS ready: " .. ttsMethod)
    end)

    ttsPanel:AddFunction("gmod", "ttsDone", function()
        isSpeaking = false
    end)

    ttsPanel:AddFunction("gmod", "ttsError", function(err)
        print("[Smart Maniac] TTS error: " .. tostring(err))
        isSpeaking = false
    end)

    local html = [[
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
var synth = window.speechSynthesis;
var selectedVoice = null;
var isReady = false;

function findRussianVoice() {
    var voices = synth.getVoices();
    var maleRu = null;
    var anyRu = null;

    for (var i = 0; i < voices.length; i++) {
        var v = voices[i];
        if (v.lang && v.lang.indexOf('ru') === 0) {
            if (!anyRu) anyRu = v;
            var nameLower = v.name.toLowerCase();
            if (nameLower.indexOf('male') !== -1 || nameLower.indexOf('dmitr') !== -1 ||
                nameLower.indexOf('pavel') !== -1 || nameLower.indexOf('maxim') !== -1 ||
                nameLower.indexOf('мужск') !== -1) {
                maleRu = v;
            }
        }
    }

    selectedVoice = maleRu || anyRu;
    if (selectedVoice) {
        gmod.ttsReady('speechsynthesis');
        isReady = true;
    }
}

if (synth) {
    synth.onvoiceschanged = findRussianVoice;
    findRussianVoice();

    setTimeout(function() {
        if (!isReady) {
            findRussianVoice();
            if (!isReady) {
                gmod.ttsReady('fallback');
            }
        }
    }, 2000);
} else {
    gmod.ttsReady('fallback');
}

function speak(text, pitch, rate, volume) {
    if (!synth || !selectedVoice) {
        gmod.ttsError('no voice');
        return;
    }

    synth.cancel();

    var utter = new SpeechSynthesisUtterance(text);
    utter.voice = selectedVoice;
    utter.lang = 'ru-RU';
    utter.pitch = pitch || 0.4;
    utter.rate = rate || 0.85;
    utter.volume = volume || 1.0;

    utter.onend = function() { gmod.ttsDone(); };
    utter.onerror = function(e) { gmod.ttsError(e.error || 'unknown'); };

    synth.speak(utter);
}

function stopSpeaking() {
    if (synth) synth.cancel();
}

function setVolume(vol) {
    // Can't change volume mid-utterance, but store for next
}
</script>
</body>
</html>
]]

    ttsPanel:SetHTML(html)
end

--- Calculate volume based on distance from local player to NPC.
local function GetDistanceVolume(npc)
    if not IsValid(npc) then return 0 end
    local lp = LocalPlayer()
    if not IsValid(lp) then return 0 end

    local dist = lp:GetPos():Distance(npc:GetPos())
    if dist > VOICE_FADE_MAX then return 0 end
    if dist < VOICE_FADE_MIN then return 1.0 end

    return 1.0 - ((dist - VOICE_FADE_MIN) / (VOICE_FADE_MAX - VOICE_FADE_MIN))
end

--- Speak using DHTML SpeechSynthesis (primary method).
local function SpeakSynthesis(npc, phrase)
    if not IsValid(ttsPanel) then return false end
    if ttsMethod ~= "speechsynthesis" then return false end

    local volume = GetDistanceVolume(npc)
    if volume <= 0 then return true end

    local pitch = VOICE_PITCH
    local rate = VOICE_RATE

    -- Read custom rate from ConVar if available
    local rateCV = GetConVar("sm_maniac_voice_tts_rate")
    if rateCV then
        rate = rateCV:GetFloat()
        pitch = math.Clamp(rate - 0.3, 0.1, 0.6)
    end

    local escaped = string.gsub(phrase, "'", "\\'")
    escaped = string.gsub(escaped, '"', '\\"')
    escaped = string.gsub(escaped, "\n", " ")

    ttsPanel:RunJavascript(string.format(
        "speak('%s', %f, %f, %f);",
        escaped, pitch, rate, volume
    ))

    isSpeaking = true
    currentSpeakingNPC = npc
    return true
end

--- Speak using Google TTS fallback with deep voice.
local function SpeakGoogleTTS(npc, phrase)
    if not IsValid(npc) then return end

    SmartManiac.TTS.StopNPC(npc)

    local chunks = SplitText(phrase)
    activeTTSChannels[npc] = activeTTSChannels[npc] or {}

    for i, chunk in ipairs(chunks) do
        local encoded = UrlEncode(chunk)
        local ttsUrl = "https://translate.google.com/translate_tts?ie=UTF-8&tl=ru&client=tw-ob&q=" .. encoded

        timer.Simple((i - 1) * 2.0, function()
            if not IsValid(npc) then return end

            sound.PlayURL(ttsUrl, "3d mono", function(channel, errorID, errorName)
                if not IsValid(channel) then
                    print("[Smart Maniac] TTS fallback error: " .. tostring(errorName))
                    return
                end

                if not IsValid(npc) then
                    channel:Stop()
                    return
                end

                activeTTSChannels[npc] = activeTTSChannels[npc] or {}
                table.insert(activeTTSChannels[npc], channel)

                channel:SetPos(npc:GetPos() + Vector(0, 0, 60))
                channel:Set3DFadeDistance(VOICE_FADE_MIN, VOICE_FADE_MAX)
                channel:SetVolume(VOICE_VOLUME)
                channel:SetPlaybackRate(GTTS_PLAYBACK_RATE)
                channel:Play()
            end)

            -- Echo effect: second channel slightly delayed at lower volume
            timer.Simple(0.12, function()
                if not IsValid(npc) then return end

                sound.PlayURL(ttsUrl, "3d mono", function(channel)
                    if not IsValid(channel) or not IsValid(npc) then
                        if IsValid(channel) then channel:Stop() end
                        return
                    end

                    activeTTSChannels[npc] = activeTTSChannels[npc] or {}
                    table.insert(activeTTSChannels[npc], channel)

                    channel:SetPos(npc:GetPos() + Vector(0, 0, 60))
                    channel:Set3DFadeDistance(VOICE_FADE_MIN, VOICE_FADE_MAX)
                    channel:SetVolume(VOICE_VOLUME * 0.3)
                    channel:SetPlaybackRate(GTTS_PLAYBACK_RATE * 0.92)
                    channel:Play()
                end)
            end)
        end)
    end
end

--- Speak a phrase as audio near an NPC.
function SmartManiac.TTS.Speak(npc, phrase)
    if not IsValid(npc) then return end
    if not phrase or phrase == "" then return end

    phrase = string.gsub(phrase, '^"', "")
    phrase = string.gsub(phrase, '"$', "")
    phrase = string.Trim(phrase)
    if phrase == "" then return end

    -- Try SpeechSynthesis first, fall back to Google TTS
    if not SpeakSynthesis(npc, phrase) then
        SpeakGoogleTTS(npc, phrase)
    end
end

--- Stop all TTS playback for an NPC.
function SmartManiac.TTS.StopNPC(npc)
    if activeTTSChannels[npc] then
        if istable(activeTTSChannels[npc]) then
            for _, ch in ipairs(activeTTSChannels[npc]) do
                if IsValid(ch) then ch:Stop() end
            end
        elseif IsValid(activeTTSChannels[npc]) then
            activeTTSChannels[npc]:Stop()
        end
        activeTTSChannels[npc] = nil
    end

    if IsValid(ttsPanel) and currentSpeakingNPC == npc then
        ttsPanel:RunJavascript("stopSpeaking();")
        isSpeaking = false
        currentSpeakingNPC = nil
    end
end

--- Check if an NPC is currently speaking.
function SmartManiac.TTS.IsSpeaking(npc)
    if isSpeaking and currentSpeakingNPC == npc then return true end

    if activeTTSChannels[npc] and istable(activeTTSChannels[npc]) then
        for _, ch in ipairs(activeTTSChannels[npc]) do
            if IsValid(ch) and ch:GetState() == GMOD_CHANNEL_PLAYING then
                return true
            end
        end
    end

    return false
end

--- Get TTS method.
function SmartManiac.TTS.GetMethod()
    return ttsMethod
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

-- Cleanup stopped channels periodically
timer.Create("SmartManiac_TTS_Cleanup", 5, 0, function()
    for npc, channels in pairs(activeTTSChannels) do
        if not IsValid(npc) then
            if istable(channels) then
                for _, ch in ipairs(channels) do
                    if IsValid(ch) then ch:Stop() end
                end
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
end)

-- Initialize TTS panel
hook.Add("InitPostEntity", "SmartManiac_TTSInit", function()
    timer.Simple(1, function()
        InitTTSPanel()
    end)
end)

print("[Smart Maniac] TTS module loaded (deep male voice + SpeechSynthesis).")
