--[[
    Smart Maniac NPC - Voice Detection System (Client)
    Detects when the local player starts/stops using voice chat,
    sends status to the server, and triggers the voice capture
    system for speech-to-text recognition.
]]

--- Send voice status to server and start voice capture when player starts speaking.
hook.Add("PlayerStartVoice", "SmartManiac_VoiceStart", function(ply)
    if ply ~= LocalPlayer() then return end

    net.Start("SmartManiac_VoiceStatus")
        net.WriteBool(true)
    net.SendToServer()

    -- Start speech recognition capture
    if SmartManiac.VoiceCapture and SmartManiac.VoiceCapture.StartCapture then
        SmartManiac.VoiceCapture.StartCapture()
    end
end)

--- Send voice status to server and stop voice capture when player stops speaking.
hook.Add("PlayerEndVoice", "SmartManiac_VoiceEnd", function(ply)
    if ply ~= LocalPlayer() then return end

    net.Start("SmartManiac_VoiceStatus")
        net.WriteBool(false)
    net.SendToServer()

    -- Stop speech recognition capture and process results
    if SmartManiac.VoiceCapture and SmartManiac.VoiceCapture.StopCapture then
        SmartManiac.VoiceCapture.StopCapture()
    end
end)
