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

-- Load server modules
include("smart_maniac/sv_ai_brain.lua")
include("smart_maniac/sv_voice_detection.lua")
include("smart_maniac/sv_openai.lua")
include("smart_maniac/sv_sound_system.lua")
include("smart_maniac/sv_conversation.lua")

-- Register network strings
util.AddNetworkString("SmartManiac_Phrase")
util.AddNetworkString("SmartManiac_VoiceDetected")
util.AddNetworkString("SmartManiac_VoiceStatus")
util.AddNetworkString("SmartManiac_StateChanged")

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

    local body = util.TableToJSON({
        model = model,
        messages = {
            { role = "system", content = "Reply with exactly: SMART MANIAC WORKS" },
            { role = "user", content = "Test" },
        },
        max_tokens = 20,
    })

    HTTP({
        url     = apiUrl,
        method  = "POST",
        headers = {
            ["Content-Type"]  = "application/json",
            ["Authorization"] = "Bearer " .. apiKey,
        },
        body    = body,
        type    = "application/json",
        success = function(code, responseBody)
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
        failed = function(err)
            msg("[Smart Maniac] FAILED: " .. tostring(err))
            msg("[Smart Maniac] This usually means GMod cannot make HTTP requests.")
            msg("[Smart Maniac] Make sure you are hosting a server (not singleplayer listen server).")
        end,
    })
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

print("[Smart Maniac] Server module loaded successfully!")
