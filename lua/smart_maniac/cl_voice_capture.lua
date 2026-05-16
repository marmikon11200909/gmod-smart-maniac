--[[
    Smart Maniac NPC - Voice Capture & Speech Recognition (Client) - MAXIMUM FIX
    
    Uses DHTML panel with Web Speech API for real-time speech recognition.
    
    Key improvements:
    - Extended listening: keeps recording for grace period after V release
    - Accumulates all speech into single transcript before sending
    - Silence detection: only sends after player stops talking
    - Robust initialization with auto-retry
    - Better error recovery and status reporting
    - Shows live transcription via subtitle system
]]

SmartManiac = SmartManiac or {}
SmartManiac.VoiceCapture = SmartManiac.VoiceCapture or {}

local dhtmlPanel = nil
local isRecording = false
local lastTranscript = ""
local accumulatedTranscript = ""
local recognitionReady = false
local captureMethod = "none"
local initAttempts = 0
local MAX_INIT_ATTEMPTS = 3

-- Timing configuration
local GRACE_PERIOD = 4.0        -- Keep listening 4 sec after V released
local SILENCE_TIMEOUT = 2.5     -- Send transcript after 2.5 sec silence
local SEND_COOLDOWN = 2.0       -- Min time between sends

local nextSendTime = 0
local voiceKeyHeld = false
local lastSpeechTime = 0
local captureStartTime = 0

--- Send accumulated transcript to the server.
local function SendAccumulatedTranscript()
    local text = string.Trim(accumulatedTranscript)
    if text == "" then return end
    if CurTime() < nextSendTime then return end

    nextSendTime = CurTime() + SEND_COOLDOWN

    if #text > 500 then
        text = string.sub(text, 1, 500)
    end

    net.Start("SmartManiac_VoiceTranscript")
        net.WriteString(text)
    net.SendToServer()

    if SmartManiac.Subtitles and SmartManiac.Subtitles.Add then
        SmartManiac.Subtitles.Add("\xd0\x92\xd1\x8b", text, Color(100, 180, 255), 5)
    end

    print("[Smart Maniac] Sent voice transcript: " .. text)
    accumulatedTranscript = ""
    lastTranscript = text
end

--- Initialize the DHTML panel for speech recognition.
function SmartManiac.VoiceCapture.Init()
    if IsValid(dhtmlPanel) then
        dhtmlPanel:Remove()
    end

    initAttempts = initAttempts + 1
    print("[Smart Maniac] Initializing voice capture (attempt " .. initAttempts .. ")")

    dhtmlPanel = vgui.Create("DHTML")
    dhtmlPanel:SetSize(1, 1)
    dhtmlPanel:SetPos(0, 0)
    dhtmlPanel:SetVisible(false)
    dhtmlPanel:SetAlpha(0)

    dhtmlPanel:AddFunction("gmod", "receiveTranscript", function(text, isFinal)
        if not text or text == "" then return end

        lastSpeechTime = CurTime()

        if isFinal then
            if accumulatedTranscript ~= "" then
                accumulatedTranscript = accumulatedTranscript .. " " .. text
            else
                accumulatedTranscript = text
            end
            lastTranscript = text
            print("[Smart Maniac] Speech (final): " .. text)

            if SmartManiac.Subtitles and SmartManiac.Subtitles.SetLive then
                SmartManiac.Subtitles.SetLive(accumulatedTranscript)
            end
        else
            local liveDisplay = accumulatedTranscript ~= "" and (accumulatedTranscript .. " " .. text) or text
            if SmartManiac.Subtitles and SmartManiac.Subtitles.SetLive then
                SmartManiac.Subtitles.SetLive(liveDisplay)
            end
        end

        timer.Remove("SmartManiac_SilenceTimer")
        timer.Create("SmartManiac_SilenceTimer", SILENCE_TIMEOUT, 1, function()
            if accumulatedTranscript ~= "" then
                SendAccumulatedTranscript()
            end
            if SmartManiac.Subtitles and SmartManiac.Subtitles.ClearLive then
                SmartManiac.Subtitles.ClearLive()
            end
        end)
    end)

    dhtmlPanel:AddFunction("gmod", "recognitionReady", function(method)
        recognitionReady = true
        captureMethod = method or "webspeech"
        print("[Smart Maniac] Speech recognition ready: " .. captureMethod)
    end)

    dhtmlPanel:AddFunction("gmod", "recognitionError", function(err)
        print("[Smart Maniac] Speech recognition error: " .. tostring(err))
        if err == "not-allowed" or err == "service-not-allowed" then
            print("[Smart Maniac] Microphone access denied - voice AI will use contextual mode")
            captureMethod = "denied"
        end
    end)

    dhtmlPanel:AddFunction("gmod", "recognitionEnded", function()
        if isRecording and IsValid(dhtmlPanel) then
            timer.Simple(0.2, function()
                if isRecording and IsValid(dhtmlPanel) then
                    dhtmlPanel:RunJavascript("startListening();")
                end
            end)
        end
    end)

    local html = [==[
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
var recognition = null;
var isListening = false;
var restartCount = 0;
var maxRestarts = 50;

function initRecognition() {
    var SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
        gmod.recognitionError("SpeechRecognition API not available");
        return false;
    }

    recognition = new SpeechRecognition();
    recognition.lang = 'ru-RU';
    recognition.interimResults = true;
    recognition.continuous = true;
    recognition.maxAlternatives = 1;

    recognition.onresult = function(event) {
        var interimTranscript = '';
        var finalTranscript = '';
        for (var i = event.resultIndex; i < event.results.length; i++) {
            var transcript = event.results[i][0].transcript;
            if (event.results[i].isFinal) {
                finalTranscript += transcript;
            } else {
                interimTranscript += transcript;
            }
        }
        if (finalTranscript.trim() !== '') {
            gmod.receiveTranscript(finalTranscript.trim(), true);
        }
        if (interimTranscript.trim() !== '') {
            gmod.receiveTranscript(interimTranscript.trim(), false);
        }
    };

    recognition.onerror = function(event) {
        if (event.error === 'no-speech' || event.error === 'aborted') return;
        gmod.recognitionError(event.error);
    };

    recognition.onend = function() {
        gmod.recognitionEnded();
        if (isListening && restartCount < maxRestarts) {
            restartCount++;
            setTimeout(function() {
                if (isListening && recognition) {
                    try { recognition.start(); } catch(e) {}
                }
            }, 200);
        }
    };

    gmod.recognitionReady('webspeech');
    return true;
}

function startListening() {
    if (!recognition) { if (!initRecognition()) return; }
    if (isListening) return;
    restartCount = 0;
    isListening = true;
    try {
        recognition.start();
    } catch(e) {
        try {
            recognition.stop();
            setTimeout(function() {
                try { recognition.start(); } catch(e2) {
                    gmod.recognitionError(e2.message || 'start_failed');
                }
            }, 200);
        } catch(e2) {
            gmod.recognitionError(e.message || 'start_failed');
        }
    }
}

function stopListening() {
    isListening = false;
    restartCount = maxRestarts;
    if (!recognition) return;
    try { recognition.stop(); } catch(e) {}
}

initRecognition();
</script>
</body>
</html>
]==]

    dhtmlPanel:SetHTML(html)

    timer.Simple(5, function()
        if not recognitionReady and initAttempts < MAX_INIT_ATTEMPTS then
            print("[Smart Maniac] Speech recognition not ready, retrying...")
            SmartManiac.VoiceCapture.Init()
        end
    end)
end

--- Start capturing voice / speech recognition.
function SmartManiac.VoiceCapture.StartCapture()
    voiceKeyHeld = true
    timer.Remove("SmartManiac_GraceTimer")

    if isRecording then return end
    isRecording = true
    accumulatedTranscript = ""
    captureStartTime = CurTime()

    if SmartManiac.Subtitles and SmartManiac.Subtitles.ShowListening then
        SmartManiac.Subtitles.ShowListening(true)
    end

    if IsValid(dhtmlPanel) and recognitionReady then
        dhtmlPanel:RunJavascript("startListening();")
        print("[Smart Maniac] Voice capture started")
    elseif not IsValid(dhtmlPanel) then
        SmartManiac.VoiceCapture.Init()
        timer.Simple(1, function()
            if IsValid(dhtmlPanel) and isRecording then
                dhtmlPanel:RunJavascript("startListening();")
            end
        end)
    end
end

--- Player released V key - start grace period, don't stop immediately.
function SmartManiac.VoiceCapture.StopCapture()
    voiceKeyHeld = false

    timer.Create("SmartManiac_GraceTimer", GRACE_PERIOD, 1, function()
        if voiceKeyHeld then return end
        SmartManiac.VoiceCapture.FinalStop()
    end)
end

--- Actually stop capturing after grace period.
function SmartManiac.VoiceCapture.FinalStop()
    if not isRecording then return end
    isRecording = false

    if IsValid(dhtmlPanel) then
        dhtmlPanel:RunJavascript("stopListening();")
    end

    if SmartManiac.Subtitles and SmartManiac.Subtitles.ShowListening then
        SmartManiac.Subtitles.ShowListening(false)
    end

    timer.Simple(0.5, function()
        if accumulatedTranscript ~= "" then
            SendAccumulatedTranscript()
        end
        if SmartManiac.Subtitles and SmartManiac.Subtitles.ClearLive then
            SmartManiac.Subtitles.ClearLive()
        end
    end)

    local duration = CurTime() - captureStartTime
    print("[Smart Maniac] Voice capture stopped (duration: " .. string.format("%.1f", duration) .. "s)")
end

function SmartManiac.VoiceCapture.GetMethod()
    return captureMethod
end

function SmartManiac.VoiceCapture.IsRecording()
    return isRecording
end

function SmartManiac.VoiceCapture.IsAvailable()
    return recognitionReady
end

function SmartManiac.VoiceCapture.IsVoiceKeyHeld()
    return voiceKeyHeld
end

function SmartManiac.VoiceCapture.GetLastTranscript()
    return lastTranscript
end

function SmartManiac.VoiceCapture.GetDebugInfo()
    return {
        method = captureMethod,
        recording = isRecording,
        ready = recognitionReady,
        panelValid = IsValid(dhtmlPanel),
        accumulated = accumulatedTranscript,
        lastTranscript = lastTranscript,
        voiceKeyHeld = voiceKeyHeld,
        initAttempts = initAttempts,
    }
end

hook.Add("InitPostEntity", "SmartManiac_VoiceCaptureInit", function()
    timer.Simple(2, function()
        SmartManiac.VoiceCapture.Init()
    end)
end)

print("[Smart Maniac] Voice capture module loaded (extended listening, grace period " .. GRACE_PERIOD .. "s).")
