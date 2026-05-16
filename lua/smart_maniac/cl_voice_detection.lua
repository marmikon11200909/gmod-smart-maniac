--[[
    Smart Maniac NPC - Voice Detection System (Client)
    Detects when the local player starts/stops using voice chat
    and sends a net message to the server.

    PlayerStartVoice / PlayerEndVoice are client-side hooks in GMod.
]]

--- Send voice status to server when player starts speaking.
hook.Add("PlayerStartVoice", "SmartManiac_VoiceStart", function(ply)
    if ply ~= LocalPlayer() then return end

    net.Start("SmartManiac_VoiceStatus")
        net.WriteBool(true)
    net.SendToServer()
end)

--- Send voice status to server when player stops speaking.
hook.Add("PlayerEndVoice", "SmartManiac_VoiceEnd", function(ply)
    if ply ~= LocalPlayer() then return end

    net.Start("SmartManiac_VoiceStatus")
        net.WriteBool(false)
    net.SendToServer()
end)
