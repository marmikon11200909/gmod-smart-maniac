--[[
    Smart Maniac NPC - Client-side Entity
    Renders floating phrases, state indicators, and visual effects.
]]

include("shared.lua")

-- ============================================================
-- Phrase display system
-- ============================================================

local activeManiacPhrases = {}  -- { [entity] = { text, startTime, duration } }

-- NOTE: SmartManiac_Phrase is handled by cl_subtitles.lua (TTS + bottom subtitles).
-- This hook updates the 3D phrase bubble above the NPC's head.
hook.Add("SmartManiac_PhraseReceived", "SmartManiac_3DPhrase", function(npc, phrase, speechType)
    if not IsValid(npc) then return end

    activeManiacPhrases[npc] = {
        text      = phrase,
        startTime = CurTime(),
        duration  = math.Clamp(#phrase * 0.08, 2, 6),
        speechType = speechType or "proactive",
    }
end)

-- ============================================================
-- Voice detection indicator
-- ============================================================

local voiceAlerts = {}

net.Receive("SmartManiac_VoiceDetected", function()
    local npc = net.ReadEntity()
    local ply = net.ReadEntity()

    if not IsValid(npc) then return end

    voiceAlerts[npc] = {
        startTime = CurTime(),
        duration  = 2,
        player    = ply,
    }
end)

-- ============================================================
-- State change effects
-- ============================================================

net.Receive("SmartManiac_StateChanged", function()
    local npc      = net.ReadEntity()
    local newState = net.ReadInt(8)

    if not IsValid(npc) then return end

    -- Chase state: red flash effect
    if newState == 3 then -- STATE_CHASE
        local ef = EffectData()
        ef:SetOrigin(npc:GetPos() + Vector(0, 0, 60))
        ef:SetScale(2)
        util.Effect("cball_explode", ef)
    end
end)

-- ============================================================
-- 3D rendering: phrases, eye glow, state icons
-- ============================================================

local stateColors = {
    [0] = Color(150, 150, 150),  -- IDLE
    [1] = Color(100, 200, 100),  -- PATROL
    [2] = Color(255, 200, 50),   -- INVESTIGATE
    [3] = Color(255, 50, 50),    -- CHASE
    [4] = Color(255, 0, 0),      -- ATTACK
    [5] = Color(200, 100, 50),   -- LOST
}

hook.Add("PostDrawTranslucentRenderables", "SmartManiac_Draw3D", function(_, _, skybox)
    if skybox then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) then continue end

        local pos = npc:GetPos() + Vector(0, 0, 85)
        local dist = lp:GetPos():Distance(npc:GetPos())

        if dist > 2000 then continue end

        local ang = (lp:EyePos() - pos):Angle()
        ang:RotateAroundAxis(ang:Up(), -90)
        ang:RotateAroundAxis(ang:Forward(), 90)

        -- -------------------------------------------------------
        -- Eye glow
        -- -------------------------------------------------------
        local eyePos = npc:GetPos() + Vector(0, 0, 64)
        local state = npc:GetManiacState()
        local eyeColor = (state == 3 or state == 4) and Color(255, 0, 0, 255) or Color(200, 0, 0, 150)

        render.SetMaterial(Material("sprites/light_glow02_add"))
        local glowSize = (state == 3 or state == 4) and 15 or 8
        glowSize = glowSize + math.sin(CurTime() * 4) * 3
        render.DrawSprite(eyePos + npc:GetForward() * 8 + npc:GetRight() * 3, glowSize, glowSize, eyeColor)
        render.DrawSprite(eyePos + npc:GetForward() * 8 - npc:GetRight() * 3, glowSize, glowSize, eyeColor)

        -- -------------------------------------------------------
        -- State indicator (small, above head)
        -- -------------------------------------------------------
        if dist < 800 then
            local stateColor = stateColors[state] or Color(255, 255, 255)
            local stateName = npc.StateNames and npc.StateNames[state] or "Unknown"

            cam.Start3D2D(pos + Vector(0, 0, 15), ang, 0.08)
                draw.SimpleTextOutlined(
                    "[ " .. stateName .. " ]",
                    "DermaLarge",
                    0, 0, stateColor,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
                    1, Color(0, 0, 0, 200)
                )
            cam.End3D2D()
        end

        -- -------------------------------------------------------
        -- Phrase bubble
        -- -------------------------------------------------------
        local phraseData = activeManiacPhrases[npc]
        if phraseData then
            local elapsed = CurTime() - phraseData.startTime
            if elapsed > phraseData.duration then
                activeManiacPhrases[npc] = nil
            else
                local alpha = 1
                if elapsed > phraseData.duration - 1 then
                    alpha = (phraseData.duration - elapsed)
                end

                cam.Start3D2D(pos, ang, 0.1)
                    local text = phraseData.text
                    surface.SetFont("DermaLarge")
                    local tw, th = surface.GetTextSize(text)
                    local pad = 10

                    -- Background
                    local bgAlpha = math.floor(180 * alpha)
                    draw.RoundedBox(8, -tw / 2 - pad, -th / 2 - pad, tw + pad * 2, th + pad * 2,
                        Color(0, 0, 0, bgAlpha))

                    -- Text
                    local textAlpha = math.floor(255 * alpha)
                    draw.SimpleTextOutlined(
                        text,
                        "DermaLarge",
                        0, 0,
                        Color(255, 50, 50, textAlpha),
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
                        1, Color(0, 0, 0, textAlpha)
                    )
                cam.End3D2D()
            end
        end

        -- -------------------------------------------------------
        -- Voice detection warning (ear icon)
        -- -------------------------------------------------------
        local alertData = voiceAlerts[npc]
        if alertData then
            local elapsed = CurTime() - alertData.startTime
            if elapsed > alertData.duration then
                voiceAlerts[npc] = nil
            else
                local alertAlpha = math.floor(255 * (1 - elapsed / alertData.duration))
                cam.Start3D2D(pos + Vector(0, 0, 30), ang, 0.08)
                    draw.SimpleTextOutlined(
                        "🔊 VOICE DETECTED!",
                        "DermaDefault",
                        0, 0,
                        Color(255, 200, 0, alertAlpha),
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
                        1, Color(0, 0, 0, alertAlpha)
                    )
                cam.End3D2D()
            end
        end
    end
end)

-- ============================================================
-- Screen-space effects when being chased
-- ============================================================

hook.Add("RenderScreenspaceEffects", "SmartManiac_ScreenFX", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local closestDist = math.huge
    local closestState = -1

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) then continue end
        local d = lp:GetPos():Distance(npc:GetPos())
        if d < closestDist then
            closestDist = d
            closestState = npc:GetManiacState()
        end
    end

    -- Red vignette when being chased
    if (closestState == 3 or closestState == 4) and closestDist < 800 then
        local intensity = math.Clamp(1 - (closestDist / 800), 0, 0.6)
        local pulse = math.sin(CurTime() * 3) * 0.1

        DrawMaterialOverlay("effects/combine_binocoverlay", intensity * 0.3 + pulse)

        local tab = {
            ["$pp_colour_addr"]       = intensity * 0.05,
            ["$pp_colour_addg"]       = 0,
            ["$pp_colour_addb"]       = 0,
            ["$pp_colour_brightness"] = -intensity * 0.05,
            ["$pp_colour_contrast"]   = 1 + intensity * 0.1,
            ["$pp_colour_colour"]     = 1 - intensity * 0.3,
            ["$pp_colour_mulr"]       = 0,
            ["$pp_colour_mulg"]       = 0,
            ["$pp_colour_mulb"]       = 0,
        }
        DrawColorModify(tab)
    end

    -- Heartbeat sound effect when very close
    if closestDist < 300 and (closestState == 3 or closestState == 4) then
        if not lp.sm_heartbeat or CurTime() > lp.sm_heartbeat then
            surface.PlaySound("ambient/levels/canals/drip1.wav")
            local interval = math.Clamp(closestDist / 300, 0.3, 1.2)
            lp.sm_heartbeat = CurTime() + interval
        end
    end
end)
