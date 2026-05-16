--[[
    Smart Maniac NPC - Voice Capture & Speech Recognition (Client)
    Uses a hidden DHTML panel to capture microphone audio and transcribe
    player speech via Web Speech API.

    Key behavior:
    - Starts listening when player presses V (voice chat)
    - Keeps listening for a grace period AFTER player releases V
    - Accumulates all speech into a single transcript
    - Only sends to server after silence period (player finished talking)
    - Shows listening indicator via subtitle system
]]

SmartManiac = SmartManiac or {}
SmartManiac.VoiceCapture = SmartManiac.VoiceCapture or {}

local dhtmlPanel = nil
local isRecording = false
local lastTranscript = ""
local accumulatedTranscript = ""
local recognitionReady = false
local captureMethod = "none"

-- Timing configuration
local GRACE_PERIOD = 3.0
local SILENCE_TIMEOUT = 2.0
local SEND_COOLDOWN = 3.0

local nextSendTime = 0
local voiceKeyHeld = false
local lastSpeechTime = 0

--- Send accumulated transcript to the server.
local function SendAccumulatedTranscript()
    local text = string.Trim(accumulatedTranscript)
    if text == "" then return end
    if CurTime() < nextSendTime then return end

    nextSendTime = CurTime() + SEND_COOLDOWN

    net.Start("SmartManiac_VoiceTranscript")
        net.WriteString(string.sub(text, 1, 500))
    net.SendToServer()

    if SmartManiac.Subtitles and SmartManiac.Subtitles.Add then
        SmartManiac.Subtitles.Add("Вы", text, Color(100, 180, 255), 4)
    end

    print("[Smart Maniac] Sent transcript: " .. text)
    accumulatedTranscript = ""
end

--- Initialize the DHTML panel for speech recognition.
function SmartManiac.VoiceCapture.Init()
    if IsValid(dhtmlPanel) then
        dhtmlPanel:Remove()
    end

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
        else
            if SmartManiac.Subtitles and SmartManiac.Subtitles.SetLive then
                SmartManiac.Subtitles.SetLive(text)
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
    end)

    local html = [[
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
var recognition = null;
var isListening = false;

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
        if (event.error !== 'no-speech' && event.error !== 'aborted') {
            gmod.recognitionError(event.error);
        }
    };

    recognition.onend = function() {
        if (isListening) {
            try {
                setTimeout(function() {
                    if (isListening) recognition.start();
                }, 100);
            } catch(e) {}
        }
    };

    gmod.recognitionReady('webspeech');
    return true;
}

function startListening() {
    if (!recognition) {
        if (!initRecognition()) return;
    }
    if (isListening) return;

    try {
        recognition.start();
        isListening = true;
    } catch(e) {
        gmod.recognitionError(e.message);
    }
}

function stopListening() {
    isListening = false;
    if (!recognition) return;
    try {
        recognition.stop();
    } catch(e) {}
}

initRecognition();
</script>
</body>
</html>
]]

    dhtmlPanel:SetHTML(html)
end

--- Start capturing voice / speech recognition.
function SmartManiac.VoiceCapture.StartCapture()
    voiceKeyHeld = true
    timer.Remove("SmartManiac_GraceTimer")

    if isRecording then return end
    isRecording = true
    accumulatedTranscript = ""

    if SmartManiac.Subtitles and SmartManiac.Subtitles.ShowListening then
        SmartManiac.Subtitles.ShowListening(true)
    end

    if IsValid(dhtmlPanel) then
        dhtmlPanel:RunJavascript("startListening();")
    else
        SmartManiac.VoiceCapture.Init()
        timer.Simple(0.5, function()
            if IsValid(dhtmlPanel) then
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

hook.Add("InitPostEntity", "SmartManiac_VoiceCaptureInit", function()
    timer.Simple(2, function()
        SmartManiac.VoiceCapture.Init()
    end)
end)

print("[Smart Maniac] Voice capture module loaded (extended listening).")
