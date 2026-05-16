--[[
    Smart Maniac NPC - Client HUD Extras
    Additional client-side HUD elements: directional indicator, damage flash.
]]

SmartManiac = SmartManiac or {}
SmartManiac.HUD = SmartManiac.HUD or {}

-- ============================================================
-- Directional threat indicator
-- Shows an arrow pointing toward the nearest maniac when chased.
-- ============================================================

local arrowMat = Material("vgui/hud/compass_north")

hook.Add("HUDPaint", "SmartManiac_ThreatIndicator", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end

    local closestNPC   = nil
    local closestDist  = math.huge
    local closestState = -1

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) then continue end
        local d = lp:GetPos():Distance(npc:GetPos())
        if d < closestDist then
            closestDist  = d
            closestNPC   = npc
            closestState = npc:GetManiacState()
        end
    end

    if not IsValid(closestNPC) then return end

    -- Only show indicator if being chased or attacked and NPC is not visible
    if closestState ~= 3 and closestState ~= 4 then return end
    if closestDist > 1500 then return end

    -- Calculate direction
    local dir = (closestNPC:GetPos() - lp:GetPos()):GetNormalized()
    local plyForward = lp:EyeAngles():Forward()

    -- 2D angle on screen
    local angle = math.atan2(dir.y, dir.x) - math.atan2(plyForward.y, plyForward.x)

    local scrW, scrH = ScrW(), ScrH()
    local cx, cy = scrW / 2, scrH / 2
    local radius = math.min(scrW, scrH) * 0.35

    local indicatorX = cx + math.cos(angle) * radius
    local indicatorY = cy - math.sin(angle) * radius

    -- Pulsating size
    local size = 24 + math.sin(CurTime() * 5) * 6
    local alpha = math.Clamp(255 * (1 - closestDist / 1500), 80, 255)

    -- Draw arrow
    surface.SetDrawColor(255, 0, 0, alpha)
    surface.SetMaterial(arrowMat)

    local drawAngle = -math.deg(angle) + 90
    surface.DrawTexturedRectRotated(indicatorX, indicatorY, size, size, drawAngle)

    -- Distance text
    if closestDist < 600 then
        local distText = math.Round(closestDist) .. "m"
        draw.SimpleTextOutlined(distText, "DermaDefault", indicatorX, indicatorY + size,
            Color(255, 100, 100, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP,
            1, Color(0, 0, 0, alpha))
    end
end)

-- ============================================================
-- Damage flash when hit by maniac
-- ============================================================


-- ============================================================
-- Atmosphere: fog-like overlay when maniac is nearby
-- ============================================================

hook.Add("HUDPaint", "SmartManiac_AtmosphereOverlay", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() then return end

    local closestDist = math.huge

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) then continue end
        local d = lp:GetPos():Distance(npc:GetPos())
        if d < closestDist then
            closestDist = d
        end
    end

    -- Subtle dark overlay when a maniac is within range
    if closestDist < 1000 then
        local intensity = math.Clamp(1 - (closestDist / 1000), 0, 0.3)
        local alpha = math.floor(intensity * 80)

        surface.SetDrawColor(0, 0, 0, alpha)
        surface.DrawRect(0, 0, ScrW(), ScrH())

        -- Subtle red corners (vignette)
        local cornerAlpha = math.floor(intensity * 40)
        local cornerSize = ScrW() * 0.3

        surface.SetDrawColor(80, 0, 0, cornerAlpha)
        surface.DrawRect(0, 0, cornerSize, cornerSize)
        surface.DrawRect(ScrW() - cornerSize, 0, cornerSize, cornerSize)
        surface.DrawRect(0, ScrH() - cornerSize, cornerSize, cornerSize)
        surface.DrawRect(ScrW() - cornerSize, ScrH() - cornerSize, cornerSize, cornerSize)
    end
end)

print("[Smart Maniac] Client HUD module loaded.")
