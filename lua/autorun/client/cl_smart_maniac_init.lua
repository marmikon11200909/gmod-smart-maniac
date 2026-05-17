--[[
    Smart Maniac NPC - Client Autorun
    Loads client-side modules and registers spawn menu entries.
]]

-- Load shared config
include("smart_maniac/sh_config.lua")

-- Load client HUD extras (directional indicator, atmosphere overlay)
include("smart_maniac/cl_hud.lua")

-- Load client voice detection (sends voice status to server)
include("smart_maniac/cl_voice_detection.lua")

-- Load client TTS (text-to-speech voice output)
include("smart_maniac/cl_tts.lua")

-- Load subtitle display system
include("smart_maniac/cl_subtitles.lua")

-- Load client voice capture (speech recognition via DHTML)
include("smart_maniac/cl_voice_capture.lua")

-- Load client API relay (SSL fix: routes HTTP requests through DHTML fetch)
include("smart_maniac/cl_api_relay.lua")

-- ============================================================
-- Spawn menu registration
-- ============================================================

list.Set("NPC", "npc_smart_maniac", {
    Name     = "Smart Maniac",
    Class    = "npc_smart_maniac",
    Category = "Smart Maniac",
})

-- ============================================================
-- Spawnmenu tool panel for configuration
-- ============================================================

hook.Add("PopulateToolMenu", "SmartManiac_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "Smart Maniac", "sm_maniac_settings", "Settings", "", "", function(panel)
        panel:ClearControls()

        panel:Help("=== Smart Maniac NPC Settings ===")
        panel:Help("Configure the AI-powered maniac NPC.")

        panel:CheckBox("Enable Maniac NPC", "sm_maniac_enabled")

        panel:NumSlider("Sight Range", "sm_maniac_sight_range", 200, 5000, 0)
        panel:NumSlider("Hearing Range", "sm_maniac_hearing_range", 100, 3000, 0)
        panel:NumSlider("Voice Chat Range", "sm_maniac_voice_range", 200, 5000, 0)

        panel:NumSlider("Walk Speed", "sm_maniac_walk_speed", 20, 200, 0)
        panel:NumSlider("Run Speed", "sm_maniac_run_speed", 100, 500, 0)

        panel:NumSlider("Health", "sm_maniac_health", 50, 5000, 0)
        panel:NumSlider("Attack Damage", "sm_maniac_damage", 5, 200, 0)

        panel:Help("")
        panel:Help("=== AI Integration ===")
        panel:Help("Enable AI-generated phrases and voice conversation.")
        panel:CheckBox("Enable AI (OpenAI/OpenRouter)", "sm_maniac_openai_enabled")
        panel:TextEntry("API Key", "sm_maniac_openai_key")
        panel:TextEntry("Model", "sm_maniac_openai_model")
        panel:TextEntry("Provider (openai/openrouter)", "sm_maniac_openai_provider")

        panel:Help("")
        panel:Help("=== Voice AI ===")
        panel:Help("Voice chat recognition and AI conversation.")
        panel:Help("Speak through voice chat near the maniac!")
        panel:CheckBox("Enable Voice AI", "sm_maniac_voice_ai")
        panel:NumSlider("Voice Depth (lower=deeper)", "sm_maniac_voice_tts_rate", 0.5, 1.0, 2)

        panel:Help("")
        panel:Help("=== Console Commands ===")
        panel:Help("sm_maniac_spawn - Spawn a maniac")
        panel:Help("sm_maniac_remove_all - Remove all maniacs")
        panel:Help("sm_maniac_reload_config - Reload config")
        panel:Help("sm_maniac_test_openai - Test AI connection")
        panel:Help("sm_maniac_voice_status - Check voice AI status")

        panel:Button("Spawn Maniac", "sm_maniac_spawn")
        panel:Button("Remove All Maniacs", "sm_maniac_remove_all")
        panel:Button("Reload Config", "sm_maniac_reload_config")
        panel:Button("Test AI Connection", "sm_maniac_test_openai")
    end)
end)

-- ============================================================
-- Kill notification
-- ============================================================

hook.Add("AddDeathNotice", "SmartManiac_DeathNotice", function(attacker, attackerTeam, inflictor, victim, victimTeam)
    -- Custom death notice handling could go here
end)

-- ============================================================
-- Minimap / compass indicator (optional HUD)
-- ============================================================

local showDebugHUD = CreateClientConVar("sm_maniac_debug_hud", "0", true, false, "Show debug HUD for maniac NPC")

hook.Add("HUDPaint", "SmartManiac_DebugHUD", function()
    if not showDebugHUD:GetBool() then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local y = 10
    draw.SimpleTextOutlined("Smart Maniac Debug HUD", "DermaDefaultBold", 10, y, Color(255, 100, 100), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0))
    y = y + 20

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) then continue end

        local dist = math.Round(lp:GetPos():Distance(npc:GetPos()))
        local state = npc:GetManiacState()
        local stateName = npc.StateNames and npc.StateNames[state] or "Unknown"
        local target = npc:GetManiacTarget()
        local targetName = IsValid(target) and target:Nick() or "None"

        local text = string.format("Maniac #%d | State: %s | Target: %s | Dist: %d",
            npc:EntIndex(), stateName, targetName, dist)

        draw.SimpleTextOutlined(text, "DermaDefault", 10, y, Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0))
        y = y + 18
    end
end)

-- ============================================================
-- Proximity warning sound
-- ============================================================

local nextWarning = 0

hook.Add("Think", "SmartManiac_ProximityWarning", function()
    if CurTime() < nextWarning then return end

    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) then continue end

        local dist = lp:GetPos():Distance(npc:GetPos())
        local state = npc:GetManiacState()

        -- Proximity breathing when maniac is close but hasn't spotted you yet
        if dist < 400 and state ~= 3 and state ~= 4 then
            surface.PlaySound("ambient/levels/canals/drip3.wav")
            nextWarning = CurTime() + 3
            break
        end
    end
end)

-- ============================================================
-- Voice AI status command
-- ============================================================

concommand.Add("sm_maniac_voice_status", function()
    print("[Smart Maniac] === Voice AI Status ===")

    -- Voice capture info
    if SmartManiac.VoiceCapture then
        local info = SmartManiac.VoiceCapture.GetDebugInfo and SmartManiac.VoiceCapture.GetDebugInfo() or {}
        print("[Smart Maniac] Capture method: " .. tostring(info.method or "unknown"))
        print("[Smart Maniac] Currently recording: " .. tostring(info.recording or false))
        print("[Smart Maniac] Recognition ready: " .. tostring(info.ready or false))
        print("[Smart Maniac] DHTML panel valid: " .. tostring(info.panelValid or false))
        print("[Smart Maniac] Voice key held: " .. tostring(info.voiceKeyHeld or false))
        print("[Smart Maniac] Init attempts: " .. tostring(info.initAttempts or 0))
        if info.lastTranscript and info.lastTranscript ~= "" then
            print("[Smart Maniac] Last transcript: " .. info.lastTranscript)
        end
    else
        print("[Smart Maniac] Voice capture module not loaded!")
    end

    -- TTS info
    if SmartManiac.TTS then
        local ttsInfo = SmartManiac.TTS.GetDebugInfo and SmartManiac.TTS.GetDebugInfo() or {}
        print("[Smart Maniac] TTS method: " .. tostring(SmartManiac.TTS.GetMethod and SmartManiac.TTS.GetMethod() or "unknown"))
        print("[Smart Maniac] TTS panel valid: " .. tostring(ttsInfo.panelValid or false))
        print("[Smart Maniac] TTS ready: " .. tostring(ttsInfo.ttsReady or false))
        print("[Smart Maniac] Active TTS channels: " .. tostring(ttsInfo.activeChannels or 0))
    else
        print("[Smart Maniac] TTS module not loaded!")
    end

    print("[Smart Maniac] === Instructions ===")
    print("[Smart Maniac] 1. In console: sm_maniac_setup YOUR_OPENROUTER_KEY")
    print("[Smart Maniac] 2. sm_maniac_spawn")
    print("[Smart Maniac] 3. Walk up to maniac and press V to talk")
    print("[Smart Maniac] 4. Maniac will also talk on his own near you!")
end)

print("[Smart Maniac] Client module loaded successfully!")
