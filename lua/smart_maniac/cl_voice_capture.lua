--[[
    Smart Maniac NPC - Voice Capture & Speech Recognition (Client)
    Uses a hidden DHTML panel to capture microphone audio and transcribe
    player speech via Web Speech API or Whisper-compatible STT endpoint.
    Transcribed text is sent to the server for AI response generation.

    Flow:
    1. PlayerStartVoice -> start recording / recognition
    2. PlayerEndVoice   -> stop recording, finalize transcription
    3. Send transcribed text to server via net message
    4. Server generates AI response via OpenRouter
    5. Response comes back as TTS phrase
]]

SmartManiac = SmartManiac or {}
SmartManiac.VoiceCapture = SmartManiac.VoiceCapture or {}

local dhtmlPanel = nil
local isRecording = false
local lastTranscript = ""
local pendingTranscript = ""
local recognitionReady = false
local captureMethod = "none" -- "webspeech", "whisper", or "none"

-- Cooldown to avoid spamming the server
local nextSendTime = 0
local SEND_COOLDOWN = 2

--- Send a transcript to the server for AI processing.
local function SendTranscript(text)
    if not text or text == "" then return end
    if CurTime() < nextSendTime then return end

    nextSendTime = CurTime() + SEND_COOLDOWN

    net.Start("SmartManiac_VoiceTranscript")
        net.WriteString(string.sub(text, 1, 500))
    net.SendToServer()

    print("[Smart Maniac] Voice transcript sent: " .. text)
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

    dhtmlPanel:AddFunction("gmod", "receiveTranscript", function(text)
        if text and text ~= "" then
            pendingTranscript = text
            lastTranscript = text
            print("[Smart Maniac] Speech recognized: " .. text)
        end
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
        var finalTranscript = '';
        for (var i = event.resultIndex; i < event.results.length; i++) {
            if (event.results[i].isFinal) {
                finalTranscript += event.results[i][0].transcript;
            }
        }
        if (finalTranscript.trim() !== '') {
            gmod.receiveTranscript(finalTranscript.trim());
        }
    };

    recognition.onerror = function(event) {
        if (event.error !== 'no-speech' && event.error !== 'aborted') {
            gmod.recognitionError(event.error);
        }
    };

    recognition.onend = function() {
        isListening = false;
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
    if (!recognition || !isListening) return;
    try {
        recognition.stop();
        isListening = false;
    } catch(e) {}
}

// Try to initialize on load
initRecognition();
</script>
</body>
</html>
]]

    dhtmlPanel:SetHTML(html)
end

--- Start capturing voice / speech recognition.
function SmartManiac.VoiceCapture.StartCapture()
    if isRecording then return end
    isRecording = true
    pendingTranscript = ""

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

--- Stop capturing and send any pending transcript.
function SmartManiac.VoiceCapture.StopCapture()
    if not isRecording then return end
    isRecording = false

    if IsValid(dhtmlPanel) then
        dhtmlPanel:RunJavascript("stopListening();")
    end

    -- Small delay to let final results arrive
    timer.Simple(0.3, function()
        if pendingTranscript ~= "" then
            SendTranscript(pendingTranscript)
            pendingTranscript = ""
        end
    end)
end

--- Get the current capture method.
function SmartManiac.VoiceCapture.GetMethod()
    return captureMethod
end

--- Check if currently recording.
function SmartManiac.VoiceCapture.IsRecording()
    return isRecording
end

--- Check if recognition is available.
function SmartManiac.VoiceCapture.IsAvailable()
    return recognitionReady
end

-- Initialize on load
hook.Add("InitPostEntity", "SmartManiac_VoiceCaptureInit", function()
    timer.Simple(2, function()
        SmartManiac.VoiceCapture.Init()
    end)
end)

print("[Smart Maniac] Voice capture module loaded.")
