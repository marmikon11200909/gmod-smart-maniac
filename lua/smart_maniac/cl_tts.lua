--[[
    Smart Maniac NPC - Client-side Text-to-Speech (MAXIMUM FIX)
    
    Primary method: Google Translate TTS via sound.PlayURL (most reliable in GMod)
    Secondary method: DHTML SpeechSynthesis API (if Russian voices available)
    
    Features:
    - Deep male voice via low playback rate
    - 3D positional audio attached to NPC
    - Distance-based volume fade
    - Echo effect for menacing atmosphere
    - Automatic chunk splitting for long text
    - Robust error handling and retry logic
]]

SmartManiac = SmartManiac or {}
SmartManiac.TTS = SmartManiac.TTS or {}

local ttsPanel = nil
local ttsReady = false
local ttsSynthReady = false
local activeTTSChannels = {}
local speakingNPCs = {}

-- Voice settings for deep male voice
local VOICE_PITCH = 0.35
local VOICE_RATE = 0.80
local VOICE_VOLUME = 1.0
local VOICE_FADE_MIN = 200
local VOICE_FADE_MAX = 1500

-- Google TTS settings (PRIMARY - most reliable in GMod)
local GTTS_PLAYBACK_RATE = 0.60
local GTTS_ECHO_DELAY = 0.15
local GTTS_ECHO_VOLUME = 0.25
local GTTS_ECHO_RATE_MULT = 0.90
local GTTS_CHUNK_DELAY = 2.5

-- Retry settings
local MAX_RETRIES = 2
local RETRY_DELAY = 0.5

--- URL-encode a string for use in query parameters.
local function UrlEncode(str)
    str = string.gsub(str, "([^%w _%%%-%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
    return str
end

--- Split long text into chunks at sentence/comma boundaries.
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

--- Play a single Google TTS chunk with 3D positioning.
local function PlayGoogleTTSChunk(npc, text, volume, retryCount)
    if not IsValid(npc) then return end
    retryCount = retryCount or 0

    local encoded = UrlEncode(text)
    local ttsUrl = "https://translate.google.com/translate_tts?ie=UTF-8&tl=ru&client=tw-ob&q=" .. encoded

    sound.PlayURL(ttsUrl, "3d mono", function(channel, errorID, errorName)
        if not IsValid(channel) then
            print("[Smart Maniac] TTS chunk error: " .. tostring(errorName) .. " (attempt " .. (retryCount + 1) .. ")")
            if retryCount < MAX_RETRIES then
                timer.Simple(RETRY_DELAY, function()
                    PlayGoogleTTSChunk(npc, text, volume, retryCount + 1)
                end)
            end
            return
        end

        if not IsValid(npc) then
            channel:Stop()
            return
        end

        activeTTSChannels[npc] = activeTTSChannels[npc] or {}
        table.insert(activeTTSChannels[npc], channel)

        local pos = npc:GetPos() + Vector(0, 0, 64)
        channel:SetPos(pos)
        channel:Set3DFadeDistance(VOICE_FADE_MIN, VOICE_FADE_MAX)
        channel:SetVolume(math.Clamp(volume, 0.1, 1.0))
        channel:SetPlaybackRate(GTTS_PLAYBACK_RATE)
        channel:Play()

        speakingNPCs[npc] = CurTime() + 5

        -- Echo effect: second channel slightly delayed for menacing atmosphere
        timer.Simple(GTTS_ECHO_DELAY, function()
            if not IsValid(npc) then return end

            sound.PlayURL(ttsUrl, "3d mono", function(echoChannel)
                if not IsValid(echoChannel) or not IsValid(npc) then
                    if IsValid(echoChannel) then echoChannel:Stop() end
                    return
                end

                activeTTSChannels[npc] = activeTTSChannels[npc] or {}
                table.insert(activeTTSChannels[npc], echoChannel)

                echoChannel:SetPos(npc:GetPos() + Vector(0, 0, 64))
                echoChannel:Set3DFadeDistance(VOICE_FADE_MIN, VOICE_FADE_MAX)
                echoChannel:SetVolume(math.Clamp(volume * GTTS_ECHO_VOLUME, 0.05, 0.4))
                echoChannel:SetPlaybackRate(GTTS_PLAYBACK_RATE * GTTS_ECHO_RATE_MULT)
                echoChannel:Play()
            end)
        end)
    end)
end

--- Speak using Google TTS (PRIMARY method - most reliable).
local function SpeakGoogleTTS(npc, phrase)
    if not IsValid(npc) then return end

    SmartManiac.TTS.StopNPC(npc)

    local volume = GetDistanceVolume(npc)
    if volume <= 0 then return end

    local chunks = SplitText(phrase)
    activeTTSChannels[npc] = activeTTSChannels[npc] or {}

    for i, chunk in ipairs(chunks) do
        timer.Simple((i - 1) * GTTS_CHUNK_DELAY, function()
            if not IsValid(npc) then return end
            local currentVol = GetDistanceVolume(npc)
            if currentVol <= 0 then return end
            PlayGoogleTTSChunk(npc, chunk, currentVol)
        end)
    end
end

--- Initialize the TTS DHTML panel for SpeechSynthesis (secondary method).
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
        if method == "speechsynthesis" then
            ttsSynthReady = true
        end
        print("[Smart Maniac] TTS panel ready: " .. tostring(method))
    end)

    ttsPanel:AddFunction("gmod", "ttsDone", function(npcIdx)
        -- Mark NPC done speaking via synth
    end)

    ttsPanel:AddFunction("gmod", "ttsError", function(err)
        print("[Smart Maniac] SpeechSynthesis error: " .. tostring(err))
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
    if (!synth) return;
    var voices = synth.getVoices();
    var maleRu = null;
    var anyRu = null;

    for (var i = 0; i < voices.length; i++) {
        var v = voices[i];
        if (v.lang && (v.lang.indexOf('ru') === 0 || v.lang === 'ru-RU')) {
            if (!anyRu) anyRu = v;
            var nameLower = v.name.toLowerCase();
            if (nameLower.indexOf('male') !== -1 || nameLower.indexOf('dmitr') !== -1 ||
                nameLower.indexOf('pavel') !== -1 || nameLower.indexOf('maxim') !== -1 ||
                nameLower.indexOf('мужск') !== -1 || nameLower.indexOf('yuri') !== -1) {
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
                gmod.ttsReady('fallback_only');
            }
        }
    }, 3000);
} else {
    gmod.ttsReady('fallback_only');
}

function speak(text, pitch, rate, volume) {
    if (!synth || !selectedVoice) {
        gmod.ttsError('no_russian_voice');
        return false;
    }
    synth.cancel();
    var utter = new SpeechSynthesisUtterance(text);
    utter.voice = selectedVoice;
    utter.lang = 'ru-RU';
    utter.pitch = pitch || 0.35;
    utter.rate = rate || 0.80;
    utter.volume = volume || 1.0;
    utter.onend = function() { gmod.ttsDone(0); };
    utter.onerror = function(e) { gmod.ttsError(e.error || 'unknown'); };
    synth.speak(utter);
    return true;
}

function stopSpeaking() {
    if (synth) synth.cancel();
}
</script>
</body>
</html>
]]

    ttsPanel:SetHTML(html)
end

--- Try SpeechSynthesis as bonus (may not work in GMod CEF).
local function TrySpeechSynthesis(npc, phrase)
    if not IsValid(ttsPanel) or not ttsSynthReady then return false end

    local volume = GetDistanceVolume(npc)
    if volume <= 0 then return true end

    local escaped = string.gsub(phrase, "'", "\\'")
    escaped = string.gsub(escaped, '"', '\\"')
    escaped = string.gsub(escaped, "\n", " ")
    escaped = string.gsub(escaped, "\\", "\\\\")

    ttsPanel:RunJavascript(string.format(
        "speak('%s', %f, %f, %f);",
        escaped, VOICE_PITCH, VOICE_RATE, volume
    ))

    return true
end

--- Main speak function. Always uses Google TTS (reliable), optionally also SpeechSynthesis.
function SmartManiac.TTS.Speak(npc, phrase)
    if not IsValid(npc) then return end
    if not phrase or phrase == "" then return end

    -- Clean up the phrase
    phrase = string.gsub(phrase, '^"', "")
    phrase = string.gsub(phrase, '"$', "")
    phrase = string.Trim(phrase)
    if phrase == "" then return end
    if #phrase > 500 then
        phrase = string.sub(phrase, 1, 500)
    end

    print("[Smart Maniac] TTS Speaking: " .. string.sub(phrase, 1, 80))

    -- PRIMARY: Google TTS (always works in GMod)
    SpeakGoogleTTS(npc, phrase)

    -- BONUS: Also try SpeechSynthesis if available (adds depth)
    TrySpeechSynthesis(npc, phrase)
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

    speakingNPCs[npc] = nil

    if IsValid(ttsPanel) then
        ttsPanel:RunJavascript("stopSpeaking();")
    end
end

--- Check if an NPC is currently speaking.
function SmartManiac.TTS.IsSpeaking(npc)
    if speakingNPCs[npc] and CurTime() < speakingNPCs[npc] then return true end

    if activeTTSChannels[npc] and istable(activeTTSChannels[npc]) then
        for _, ch in ipairs(activeTTSChannels[npc]) do
            if IsValid(ch) and ch:GetState() == GMOD_CHANNEL_PLAYING then
                return true
            end
        end
    end

    return false
end

--- Get current TTS method info.
function SmartManiac.TTS.GetMethod()
    if ttsSynthReady then return "google_tts + speechsynthesis" end
    return "google_tts"
end

--- Get debug info about TTS state.
function SmartManiac.TTS.GetDebugInfo()
    local info = {}
    info.panelValid = IsValid(ttsPanel)
    info.ttsReady = ttsReady
    info.synthReady = ttsSynthReady
    info.method = SmartManiac.TTS.GetMethod()
    info.activeChannels = 0
    for npc, channels in pairs(activeTTSChannels) do
        if istable(channels) then
            info.activeChannels = info.activeChannels + #channels
        end
    end
    return info
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
            speakingNPCs[npc] = nil
        elseif istable(channels) then
            local pos = npc:GetPos() + Vector(0, 0, 64)
            for _, ch in ipairs(channels) do
                if IsValid(ch) then
                    ch:SetPos(pos)
                end
            end
        end
    end
end)

-- Cleanup stopped channels periodically
timer.Create("SmartManiac_TTS_Cleanup", 3, 0, function()
    for npc, channels in pairs(activeTTSChannels) do
        if not IsValid(npc) then
            if istable(channels) then
                for _, ch in ipairs(channels) do
                    if IsValid(ch) then ch:Stop() end
                end
            end
            activeTTSChannels[npc] = nil
            speakingNPCs[npc] = nil
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

    -- Clean up expired speaking NPCs
    for npc, endTime in pairs(speakingNPCs) do
        if not IsValid(npc) or CurTime() > endTime then
            speakingNPCs[npc] = nil
        end
    end
end)

-- Initialize TTS panel on game load
hook.Add("InitPostEntity", "SmartManiac_TTSInit", function()
    timer.Simple(1, function()
        InitTTSPanel()
        print("[Smart Maniac] TTS initialized (Google TTS primary)")
    end)
end)

print("[Smart Maniac] TTS module loaded (deep male voice, Google TTS primary).")
