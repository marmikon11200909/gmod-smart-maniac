--[[
    Smart Maniac NPC - Server Autorun
    Loads all server-side modules and registers the NPC.
]]

-- Load shared config first
include("smart_maniac/sh_config.lua")
AddCSLuaFile("smart_maniac/sh_config.lua")

-- Send client modules
AddCSLuaFile("smart_maniac/cl_hud.lua")
AddCSLuaFile("smart_maniac/cl_voice_detection.lua")
AddCSLuaFile("smart_maniac/cl_tts.lua")
AddCSLuaFile("smart_maniac/cl_subtitles.lua")
AddCSLuaFile("smart_maniac/cl_voice_capture.lua")
AddCSLuaFile("smart_maniac/cl_api_relay.lua")

-- Load server modules
include("smart_maniac/sv_api_relay.lua")  -- Must load BEFORE other modules that use SmartManiac.API
include("smart_maniac/sv_ai_brain.lua")
include("smart_maniac/sv_voice_detection.lua")
include("smart_maniac/sv_openai.lua")
include("smart_maniac/sv_sound_system.lua")
include("smart_maniac/sv_conversation.lua")
include("smart_maniac/sv_voice_conversation.lua")

-- Register network strings
util.AddNetworkString("SmartManiac_Phrase")
util.AddNetworkString("SmartManiac_VoiceDetected")
util.AddNetworkString("SmartManiac_VoiceStatus")
util.AddNetworkString("SmartManiac_StateChanged")
util.AddNetworkString("SmartManiac_VoiceTranscript")
util.AddNetworkString("SmartManiac_APIRequest")
util.AddNetworkString("SmartManiac_APIResponse")

-- ============================================================
-- Admin commands
-- ============================================================

concommand.Add("sm_maniac_spawn", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges to spawn the maniac.")
        return
    end

    local tr
    if IsValid(ply) then
        tr = ply:GetEyeTrace()
    end

    local spawnPos = tr and tr.HitPos or Vector(0, 0, 0)
    if tr then
        spawnPos = spawnPos + tr.HitNormal * 10
    end

    local npc = ents.Create("npc_smart_maniac")
    if not IsValid(npc) then return end

    npc:SetPos(spawnPos)
    if IsValid(ply) then
        npc:SetAngles(Angle(0, ply:GetAngles().y + 180, 0))
    end
    npc:Spawn()
    npc:Activate()

    if IsValid(ply) then
        ply:ChatPrint("[Smart Maniac] Maniac spawned!")
    end

    print("[Smart Maniac] NPC spawned at " .. tostring(spawnPos))
end)

concommand.Add("sm_maniac_remove_all", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges.")
        return
    end

    local count = 0
    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if IsValid(npc) then
            npc:Remove()
            count = count + 1
        end
    end

    local msg = "[Smart Maniac] Removed " .. count .. " maniac(s)."
    if IsValid(ply) then
        ply:ChatPrint(msg)
    end
    print(msg)
end)

concommand.Add("sm_maniac_reload_config", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges.")
        return
    end

    SmartManiac.Config.Refresh()
    local msg = "[Smart Maniac] Configuration reloaded from ConVars."
    if IsValid(ply) then
        ply:ChatPrint(msg)
    end
    print(msg)
end)

-- ============================================================
-- OpenAI test command
-- ============================================================

concommand.Add("sm_maniac_test_openai", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges.")
        return
    end

    local enabled = GetConVar("sm_maniac_openai_enabled"):GetBool()
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local provider = GetConVar("sm_maniac_openai_provider"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    local function msg(text)
        print(text)
        if IsValid(ply) then ply:ChatPrint(text) end
    end

    msg("[Smart Maniac] === OpenAI Diagnostics ===")
    msg("[Smart Maniac] Enabled: " .. tostring(enabled))
    msg("[Smart Maniac] Key set: " .. tostring(apiKey ~= ""))
    msg("[Smart Maniac] Key length: " .. tostring(#apiKey))
    msg("[Smart Maniac] Model: " .. model)
    msg("[Smart Maniac] Provider: " .. provider)
    msg("[Smart Maniac] API URL: " .. apiUrl)

    if not enabled then
        msg("[Smart Maniac] ERROR: OpenAI disabled! Run: sm_maniac_openai_enabled 1")
        return
    end

    if apiKey == "" then
        msg("[Smart Maniac] ERROR: No API key! Run: sm_maniac_openai_key YOUR_KEY")
        return
    end

    msg("[Smart Maniac] Sending test request to OpenAI...")
    msg("[Smart Maniac] Relay mode: " .. tostring(SmartManiac.API.IsRelayMode()))

    local body = util.TableToJSON({
        model = model,
        messages = {
            { role = "system", content = "Reply with exactly: SMART MANIAC WORKS" },
            { role = "user", content = "Test" },
        },
        max_tokens = 20,
    })

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. apiKey,
    }

    SmartManiac.API.Request(apiUrl, "POST", headers, body,
        function(code, responseBody)
            msg("[Smart Maniac] HTTP response code: " .. tostring(code))
            if code == 200 then
                local data = util.JSONToTable(responseBody)
                if data and data.choices and data.choices[1] then
                    local reply = data.choices[1].message and data.choices[1].message.content or "no content"
                    msg("[Smart Maniac] SUCCESS! AI replied: " .. reply)
                else
                    msg("[Smart Maniac] ERROR: unexpected response format")
                    msg("[Smart Maniac] Raw: " .. string.sub(responseBody, 1, 200))
                end
            elseif code == 401 then
                msg("[Smart Maniac] ERROR: Invalid API key (401 Unauthorized)")
            elseif code == 403 then
                msg("[Smart Maniac] ERROR: Region blocked (403). Use: sm_maniac_openai_provider openrouter")
            elseif code == 429 then
                msg("[Smart Maniac] ERROR: Rate limit or no credits (429). Check your billing.")
            elseif code == 404 then
                msg("[Smart Maniac] ERROR: Model not found (404). Try: sm_maniac_openai_model gpt-4o-mini")
            else
                msg("[Smart Maniac] ERROR: HTTP " .. tostring(code))
                msg("[Smart Maniac] Body: " .. string.sub(responseBody, 1, 300))
            end
        end,
        function(err)
            msg("[Smart Maniac] FAILED: " .. tostring(err))
            msg("[Smart Maniac] This usually means GMod cannot make HTTP requests.")
            msg("[Smart Maniac] Try: sm_maniac_force_relay 1 (forces DHTML relay for SSL fix)")
        end
    )
end)

-- ============================================================
-- Kill announcements
-- ============================================================

hook.Add("PlayerDeath", "SmartManiac_KillAnnounce", function(victim, inflictor, attacker)
    if not IsValid(attacker) then return end
    if attacker:GetClass() ~= "npc_smart_maniac" then return end

    -- Announce the kill
    for _, ply in ipairs(player.GetAll()) do
        ply:ChatPrint("[Smart Maniac] " .. victim:Nick() .. " was killed by the Maniac!")
    end

    -- Maniac says something
    if isfunction(attacker.SayPhrase) then
        attacker:SayPhrase("attack")
    end
end)

-- ============================================================
-- Quick setup command (one command to enable everything)
-- ============================================================

concommand.Add("sm_maniac_setup", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges.")
        return
    end

    local function msg(text)
        print(text)
        if IsValid(ply) then ply:ChatPrint(text) end
    end

    if not args or #args < 1 then
        msg("[Smart Maniac] Usage: sm_maniac_setup YOUR_OPENROUTER_API_KEY")
        msg("[Smart Maniac] This will enable AI, set OpenRouter, and set your key.")
        return
    end

    local key = args[1]
    RunConsoleCommand("sm_maniac_openai_enabled", "1")
    RunConsoleCommand("sm_maniac_openai_provider", "openrouter")
    RunConsoleCommand("sm_maniac_openai_key", key)
    RunConsoleCommand("sm_maniac_voice_ai", "1")

    msg("[Smart Maniac] === Quick Setup Complete ===")
    msg("[Smart Maniac] AI: ON | Provider: OpenRouter | Voice AI: ON")
    msg("[Smart Maniac] Key set (" .. #key .. " chars)")
    msg("[Smart Maniac] Now run: sm_maniac_spawn")
    msg("[Smart Maniac] Then press V near the maniac to talk!")
end)

-- ============================================================
-- Force maniac to speak (debug command)
-- ============================================================

concommand.Add("sm_maniac_say", function(ply, cmd, args)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges.")
        return
    end

    local function msg(text)
        print(text)
        if IsValid(ply) then ply:ChatPrint(text) end
    end

    local maniacs = ents.FindByClass("npc_smart_maniac")
    if #maniacs == 0 then
        msg("[Smart Maniac] No maniacs found! Run: sm_maniac_spawn")
        return
    end

    local npc = maniacs[1]

    if args and #args > 0 then
        local phrase = table.concat(args, " ")
        SmartManiac.Sound.BroadcastPhrase(npc, phrase)
        msg("[Smart Maniac] Maniac says: " .. phrase)
    else
        if SmartManiac.VoiceConv and SmartManiac.VoiceConv.ProactiveSpeech then
            SmartManiac.VoiceConv.ProactiveSpeech(npc)
            msg("[Smart Maniac] Triggered proactive speech for maniac #" .. npc:EntIndex())
        else
            msg("[Smart Maniac] Voice conversation module not loaded!")
        end
    end
end)

-- ============================================================
-- Full voice system diagnostics
-- ============================================================

concommand.Add("sm_maniac_voice_debug", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then
        ply:ChatPrint("[Smart Maniac] You need admin privileges.")
        return
    end

    local function msg(text)
        print(text)
        if IsValid(ply) then ply:ChatPrint(text) end
    end

    msg("[Smart Maniac] === Voice System Debug ===")
    msg("[Smart Maniac] Voice AI enabled: " .. tostring(GetConVar("sm_maniac_voice_ai"):GetBool()))
    msg("[Smart Maniac] OpenAI enabled: " .. tostring(GetConVar("sm_maniac_openai_enabled"):GetBool()))
    msg("[Smart Maniac] API key set: " .. tostring(GetConVar("sm_maniac_openai_key"):GetString() ~= ""))
    msg("[Smart Maniac] Provider: " .. GetConVar("sm_maniac_openai_provider"):GetString())
    msg("[Smart Maniac] API URL: " .. SmartManiac.Config.GetAPIUrl())
    msg("[Smart Maniac] VoiceConv module: " .. tostring(SmartManiac.VoiceConv ~= nil))

    local maniacs = ents.FindByClass("npc_smart_maniac")
    msg("[Smart Maniac] Maniacs alive: " .. #maniacs)

    local speakers = SmartManiac.Voice and SmartManiac.Voice.SpeakingPlayers or {}
    local speakerCount = 0
    for _ in pairs(speakers) do speakerCount = speakerCount + 1 end
    msg("[Smart Maniac] Players speaking: " .. speakerCount)

    msg("[Smart Maniac] === Commands ===")
    msg("sm_maniac_setup KEY - Quick setup with OpenRouter")
    msg("sm_maniac_spawn - Spawn maniac")
    msg("sm_maniac_say TEXT - Make maniac say text")
    msg("sm_maniac_say - Trigger random proactive phrase")
    msg("sm_maniac_test_openai - Test AI connection")
end)

print("[Smart Maniac] Server module loaded successfully!")
