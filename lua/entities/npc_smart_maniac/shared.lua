--[[
    Smart Maniac NPC - Shared Entity Definition
]]

ENT.Type            = "ai"
ENT.Base            = "base_ai"
ENT.PrintName       = "Smart Maniac"
ENT.Author          = "SmartManiac Addon"
ENT.Category        = "Smart Maniac"
ENT.Spawnable       = true
ENT.AdminSpawnable  = true
ENT.AutomaticFrameAdvance = true

-- State name lookup (shared for HUD display)
ENT.StateNames = {
    [0] = "Idle",
    [1] = "Patrol",
    [2] = "Investigate",
    [3] = "Chase",
    [4] = "Attack",
    [5] = "Lost Target",
}

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "ManiacState")
    self:NetworkVar("Entity", 0, "ManiacTarget")
end
