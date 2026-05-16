--[[
    Smart Maniac NPC - Server-side Entity
]]

AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

-- SmartManiac modules are loaded via autorun/server/sv_smart_maniac_init.lua
-- Network strings are also registered there.

-- ============================================================
-- Entity setup
-- ============================================================

function ENT:Initialize()
    -- Model: use a creepy HL2 model
    self:SetModel("models/zombie/classic.mdl")
    self:SetHullType(HULL_HUMAN)
    self:SetHullSizeNormal()
    self:SetNPCState(NPC_STATE_SCRIPT)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_STEP)
    self:CapabilitiesAdd(bit.bor(
        CAP_MOVE_GROUND,
        CAP_OPEN_DOORS,
        CAP_ANIMATEDFACE,
        CAP_TURN_HEAD,
        CAP_USE_SHOT_REGULATOR,
        CAP_AIM_GUN
    ))

    -- Health from config
    SmartManiac.Config.Refresh()
    self:SetHealth(SmartManiac.Config.Health)
    self:SetMaxHealth(SmartManiac.Config.Health)

    -- Movement speed
    self:SetMaxLookDistance(SmartManiac.Config.SightRange)

    -- Initialize AI brain
    SmartManiac.AI.Init(self)

    -- Start thinking
    self:SetSchedule(SCHED_IDLE_STAND)

    -- Eye glow effect
    self:SetEyeTarget(self:GetPos() + self:GetForward() * 100)

    -- Relationship: hate all players
    self:AddRelationship("player D_HT 99")

    self:SetManiacState(SmartManiac.AI.STATE_IDLE)
end

function ENT:OnStateChanged(oldState, newState)
    self:SetManiacState(newState)

    -- Broadcast state change to clients
    net.Start("SmartManiac_StateChanged")
        net.WriteEntity(self)
        net.WriteInt(newState, 8)
    net.Broadcast()

    -- Play appropriate sounds on state transitions
    local AI = SmartManiac.AI
    if newState == AI.STATE_CHASE then
        self:SayPhrase("spot")
    elseif newState == AI.STATE_INVESTIGATE then
        self:SayPhrase("investigate")
    elseif newState == AI.STATE_LOST then
        self:SayPhrase("lost")
    end

    -- Adjust movement speed based on state
    if newState == AI.STATE_PATROL then
        self:SetCurrentWeaponProficiency(WEAPON_PROFICIENCY_AVERAGE)
    elseif newState == AI.STATE_CHASE or newState == AI.STATE_ATTACK then
        self:SetCurrentWeaponProficiency(WEAPON_PROFICIENCY_VERY_GOOD)
    end
end

--- Wrapper so the AI brain can call npc:SayPhrase(category).
function ENT:SayPhrase(category)
    SmartManiac.Sound.SayPhrase(self, category)
end

-- ============================================================
-- Think loop
-- ============================================================

function ENT:Think()
    if not GetConVar("sm_maniac_enabled"):GetBool() then return end

    SmartManiac.AI.Think(self)

    -- Sync the network var for the target
    if IsValid(self.sm_target) then
        self:SetManiacTarget(self.sm_target)
    end

    -- Random voice lines depending on state
    local st = self.sm_state
    if st == SmartManiac.AI.STATE_PATROL then
        if math.random(1, 80) == 1 then
            self:SayPhrase("idle")
        end
    elseif st == SmartManiac.AI.STATE_CHASE then
        if math.random(1, 60) == 1 then
            self:SayPhrase("chase")
        end
    elseif st == SmartManiac.AI.STATE_INVESTIGATE then
        if math.random(1, 100) == 1 then
            self:SayPhrase("investigate")
        end
    end

    self:NextThink(CurTime() + SmartManiac.Config.ThinkInterval)
    return true
end

-- ============================================================
-- Damage handling
-- ============================================================

function ENT:OnTakeDamage(dmg)
    self:SetHealth(self:Health() - dmg:GetDamage())

    -- Play pain sound
    SmartManiac.Sound.PlaySound(self, "pain")

    -- If damaged by a player, target them
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() then
        self.sm_target = attacker
        self.sm_lastKnownPos = attacker:GetPos()
        SmartManiac.AI.SetState(self, SmartManiac.AI.STATE_CHASE)
    end

    -- Death
    if self:Health() <= 0 then
        SmartManiac.Sound.PlaySound(self, "death")

        -- Ragdoll effect
        local ragdoll = ents.Create("prop_ragdoll")
        if IsValid(ragdoll) then
            ragdoll:SetModel(self:GetModel())
            ragdoll:SetPos(self:GetPos())
            ragdoll:SetAngles(self:GetAngles())
            ragdoll:Spawn()
            ragdoll:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

            -- Copy bone positions
            for i = 0, ragdoll:GetPhysicsObjectCount() - 1 do
                local bone = ragdoll:GetPhysicsObjectNum(i)
                if IsValid(bone) then
                    local bonePos, boneAng = self:GetBonePosition(ragdoll:TranslatePhysBoneToBone(i))
                    if bonePos then
                        bone:SetPos(bonePos)
                        bone:SetAngles(boneAng)
                    end
                end
            end

            -- Remove ragdoll after a while
            timer.Simple(30, function()
                if IsValid(ragdoll) then ragdoll:Remove() end
            end)
        end

        self:Remove()
    end
end

-- ============================================================
-- Suppressing default AI schedules – we drive behaviour ourselves
-- ============================================================

function ENT:SelectSchedule()
    -- Prevent the base AI from overriding our custom behaviour
end
