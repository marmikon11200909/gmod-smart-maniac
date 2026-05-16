--[[
    Smart Maniac NPC - Voice Detection System (Server)
    Receives voice status updates from clients and notifies nearby maniac NPCs
    so they can investigate the sound source.

    PlayerStartVoice / PlayerEndVoice are client-side hooks in GMod,
    so clients send net messages to the server when voice state changes.
]]

SmartManiac = SmartManiac or {}
SmartManiac.Voice = SmartManiac.Voice or {}

-- Track which players are currently speaking
SmartManiac.Voice.SpeakingPlayers = SmartManiac.Voice.SpeakingPlayers or {}

--- Receive voice status from clients.
net.Receive("SmartManiac_VoiceStatus", function(len, ply)
    if not IsValid(ply) then return end

    local isSpeaking = net.ReadBool()

    if isSpeaking then
        SmartManiac.Voice.SpeakingPlayers[ply] = true
    else
        SmartManiac.Voice.SpeakingPlayers[ply] = nil
    end
end)

--- Periodic check: for each speaking player, alert nearby maniac NPCs.
timer.Create("SmartManiac_VoiceCheck", 0.5, 0, function()
    -- Collect speaking players
    local speakers = {}
    for ply, _ in pairs(SmartManiac.Voice.SpeakingPlayers) do
        if IsValid(ply) and ply:Alive() then
            table.insert(speakers, ply)
        else
            SmartManiac.Voice.SpeakingPlayers[ply] = nil
        end
    end

    if #speakers == 0 then return end

    -- Find all smart maniac NPCs in the world
    local maniacs = ents.FindByClass("npc_smart_maniac")
    if #maniacs == 0 then return end

    local voiceRange = SmartManiac.Config.VoiceHearingRange

    for _, maniac in ipairs(maniacs) do
        if IsValid(maniac) and maniac:Health() > 0 then
            for _, ply in ipairs(speakers) do
                local dist = maniac:GetPos():Distance(ply:GetPos())
                if dist <= voiceRange then
                    -- The maniac "heard" this player's voice
                    SmartManiac.AI.OnVoiceHeard(maniac, ply:GetPos())

                    -- React with a phrase (cooldown handled inside SayPhrase)
                    if isfunction(maniac.SayPhrase) then
                        maniac:SayPhrase("investigate")
                    end

                    -- Notify via network for client-side effects
                    net.Start("SmartManiac_VoiceDetected")
                        net.WriteEntity(maniac)
                        net.WriteEntity(ply)
                    net.Broadcast()
                end
            end
        end
    end
end)

--- Cleanup when a player disconnects.
hook.Add("PlayerDisconnected", "SmartManiac_VoiceCleanup", function(ply)
    SmartManiac.Voice.SpeakingPlayers[ply] = nil
end)
