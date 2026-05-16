--[[
    Smart Maniac NPC - AI Brain
    Finite state machine driving the maniac's behavior.
    States: IDLE, PATROL, INVESTIGATE, CHASE, ATTACK, LOST_TARGET
]]

SmartManiac = SmartManiac or {}
SmartManiac.AI = SmartManiac.AI or {}

-- State constants
SmartManiac.AI.STATE_IDLE        = 0
SmartManiac.AI.STATE_PATROL      = 1
SmartManiac.AI.STATE_INVESTIGATE = 2
SmartManiac.AI.STATE_CHASE       = 3
SmartManiac.AI.STATE_ATTACK      = 4
SmartManiac.AI.STATE_LOST        = 5

local STATE = SmartManiac.AI

--- Initialise AI data on an NPC entity.
-- Called once when the entity spawns.
-- @param npc Entity The maniac NPC.
function SmartManiac.AI.Init(npc)
    npc.sm_state          = STATE.STATE_IDLE
    npc.sm_prevState      = STATE.STATE_IDLE
    npc.sm_target         = nil
    npc.sm_lastKnownPos   = nil
    npc.sm_investigatePos = nil
    npc.sm_stateStart     = CurTime()
    npc.sm_nextAttack     = 0
    npc.sm_nextPatrolMove = 0
    npc.sm_nextPhrase     = 0
    npc.sm_patrolPoints   = {}
    npc.sm_currentPatrol  = 0
    npc.sm_lostTime       = 0
    npc.sm_heardVoice     = {}   -- table of { pos, time } entries
    npc.sm_lastPathUpdate = 0
end

--- Transition to a new state.
-- @param npc Entity
-- @param newState number
function SmartManiac.AI.SetState(npc, newState)
    if npc.sm_state == newState then return end
    npc.sm_prevState = npc.sm_state
    npc.sm_state     = newState
    npc.sm_stateStart = CurTime()

    -- Notify the entity so it can play animations / sounds
    if isfunction(npc.OnStateChanged) then
        npc:OnStateChanged(npc.sm_prevState, newState)
    end
end

-- ============================================================
-- Visibility / hearing helpers
-- ============================================================

--- Check whether the NPC can see a player.
local function CanSeePlayer(npc, ply)
    if not IsValid(ply) or not ply:Alive() then return false end

    local dist = npc:GetPos():Distance(ply:GetPos())
    if dist > SmartManiac.Config.SightRange then return false end

    -- FOV check
    local forward = npc:GetForward()
    local toPlayer = (ply:GetPos() - npc:GetPos()):GetNormalized()
    local dot = forward:Dot(toPlayer)
    local halfAngle = math.cos(math.rad(SmartManiac.Config.SightAngle / 2))
    if dot < halfAngle then return false end

    -- Line-of-sight trace
    local tr = util.TraceLine({
        start  = npc:GetShootPos(),
        endpos = ply:EyePos(),
        filter = npc,
        mask   = MASK_VISIBLE,
    })

    return tr.Entity == ply or tr.Fraction == 1
end

--- Check if a player is making noise (running, shooting, jumping).
local function CanHearPlayer(npc, ply)
    if not IsValid(ply) or not ply:Alive() then return false end

    local dist = npc:GetPos():Distance(ply:GetPos())
    if dist > SmartManiac.Config.HearingRange then return false end

    -- Running, shooting or jumping count as noise
    local isNoisy = ply:KeyDown(IN_SPEED)
        or ply:KeyDown(IN_ATTACK)
        or ply:KeyDown(IN_JUMP)
        or (ply:GetVelocity():Length() > 200)

    return isNoisy
end

--- Find the best target among all players.
local function FindTarget(npc)
    local best     = nil
    local bestDist = math.huge

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() and ply:Team() ~= TEAM_SPECTATOR then
            if CanSeePlayer(npc, ply) then
                local d = npc:GetPos():Distance(ply:GetPos())
                if d < bestDist then
                    bestDist = d
                    best = ply
                end
            end
        end
    end

    return best
end

--- Find a player the NPC can hear (but not necessarily see).
local function FindHeardTarget(npc)
    local best     = nil
    local bestDist = math.huge

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            if CanHearPlayer(npc, ply) then
                local d = npc:GetPos():Distance(ply:GetPos())
                if d < bestDist then
                    bestDist = d
                    best = ply
                end
            end
        end
    end

    return best
end

-- ============================================================
-- Navigation helpers
-- ============================================================

local function MoveToPos(npc, pos)
    if not IsValid(npc) or not pos then return end

    -- Throttle path updates to avoid spamming
    if CurTime() - (npc.sm_lastPathUpdate or 0) < 0.5 then return end
    npc.sm_lastPathUpdate = CurTime()

    npc:SetLastPosition(pos)
    npc:SetSchedule(SCHED_FORCED_GO_RUN)
end

local function WalkToPos(npc, pos)
    if not IsValid(npc) or not pos then return end
    if CurTime() - (npc.sm_lastPathUpdate or 0) < 0.5 then return end
    npc.sm_lastPathUpdate = CurTime()

    npc:SetLastPosition(pos)
    npc:SetSchedule(SCHED_FORCED_GO)
end

local function GetRandomNavPoint(npc)
    local navAreas = navmesh.GetAllNavAreas()
    if not navAreas or #navAreas == 0 then
        -- Fallback: random point around NPC
        local ang = Angle(0, math.random(0, 360), 0)
        return npc:GetPos() + ang:Forward() * math.random(200, 600)
    end
    local area = navAreas[math.random(#navAreas)]
    return area:GetRandomPoint()
end

-- ============================================================
-- State handlers
-- ============================================================

local stateHandlers = {}

stateHandlers[STATE.STATE_IDLE] = function(npc)
    -- Check voice events even while idle
    if npc.sm_heardVoice and #npc.sm_heardVoice > 0 then
        local latest = npc.sm_heardVoice[#npc.sm_heardVoice]
        if CurTime() - latest.time < 5 then
            npc.sm_investigatePos = latest.pos
            SmartManiac.AI.SetState(npc, STATE.STATE_INVESTIGATE)
            npc.sm_heardVoice = {}
            return
        end
    end

    -- Briefly idle, then switch to patrol
    if CurTime() - npc.sm_stateStart > 2 then
        SmartManiac.AI.SetState(npc, STATE.STATE_PATROL)
    end
end

stateHandlers[STATE.STATE_PATROL] = function(npc)
    -- Look for visible targets
    local target = FindTarget(npc)
    if target then
        npc.sm_target = target
        npc.sm_lastKnownPos = target:GetPos()
        SmartManiac.AI.SetState(npc, STATE.STATE_CHASE)
        return
    end

    -- Check for heard targets
    local heardTarget = FindHeardTarget(npc)
    if heardTarget then
        npc.sm_investigatePos = heardTarget:GetPos()
        SmartManiac.AI.SetState(npc, STATE.STATE_INVESTIGATE)
        return
    end

    -- Check voice chat events
    if npc.sm_heardVoice and #npc.sm_heardVoice > 0 then
        local latest = npc.sm_heardVoice[#npc.sm_heardVoice]
        if CurTime() - latest.time < 5 then
            npc.sm_investigatePos = latest.pos
            SmartManiac.AI.SetState(npc, STATE.STATE_INVESTIGATE)
            npc.sm_heardVoice = {}
            return
        end
    end

    -- Patrol movement
    if CurTime() > npc.sm_nextPatrolMove then
        local dest = GetRandomNavPoint(npc)
        WalkToPos(npc, dest)
        npc.sm_nextPatrolMove = CurTime() + math.random(
            SmartManiac.Config.PatrolWaitMin,
            SmartManiac.Config.PatrolWaitMax
        )
    end
end

stateHandlers[STATE.STATE_INVESTIGATE] = function(npc)
    -- Check for visible target on the way
    local target = FindTarget(npc)
    if target then
        npc.sm_target = target
        npc.sm_lastKnownPos = target:GetPos()
        SmartManiac.AI.SetState(npc, STATE.STATE_CHASE)
        return
    end

    -- Update investigate position if new voice heard
    if npc.sm_heardVoice and #npc.sm_heardVoice > 0 then
        local latest = npc.sm_heardVoice[#npc.sm_heardVoice]
        if CurTime() - latest.time < 5 then
            npc.sm_investigatePos = latest.pos
            npc.sm_heardVoice = {}
        end
    end

    -- Check for heard targets (footsteps, shots)
    local heardTarget = FindHeardTarget(npc)
    if heardTarget then
        npc.sm_investigatePos = heardTarget:GetPos()
    end

    -- Move toward investigate position
    if npc.sm_investigatePos then
        local dist = npc:GetPos():Distance(npc.sm_investigatePos)
        if dist < 80 then
            -- Arrived at investigation point
            npc.sm_investigatePos = nil
            SmartManiac.AI.SetState(npc, STATE.STATE_PATROL)
            return
        end
        MoveToPos(npc, npc.sm_investigatePos)
    end

    -- Timeout
    if CurTime() - npc.sm_stateStart > SmartManiac.Config.InvestigateTime then
        SmartManiac.AI.SetState(npc, STATE.STATE_PATROL)
    end
end

stateHandlers[STATE.STATE_CHASE] = function(npc)
    local target = npc.sm_target

    -- Target gone?
    if not IsValid(target) or not target:Alive() then
        if npc.sm_lastKnownPos then
            npc.sm_investigatePos = npc.sm_lastKnownPos
            SmartManiac.AI.SetState(npc, STATE.STATE_LOST)
        else
            SmartManiac.AI.SetState(npc, STATE.STATE_PATROL)
        end
        return
    end

    local dist = npc:GetPos():Distance(target:GetPos())

    -- Close enough to attack?
    if dist <= SmartManiac.Config.CloseRange then
        SmartManiac.AI.SetState(npc, STATE.STATE_ATTACK)
        return
    end

    -- Can we still see them?
    if CanSeePlayer(npc, target) then
        npc.sm_lastKnownPos = target:GetPos()
        MoveToPos(npc, target:GetPos())
    else
        -- Lost sight – go to last known position
        npc.sm_lostTime = CurTime()
        SmartManiac.AI.SetState(npc, STATE.STATE_LOST)
    end
end

stateHandlers[STATE.STATE_ATTACK] = function(npc)
    local target = npc.sm_target

    if not IsValid(target) or not target:Alive() then
        SmartManiac.AI.SetState(npc, STATE.STATE_PATROL)
        return
    end

    local dist = npc:GetPos():Distance(target:GetPos())

    if dist > SmartManiac.Config.CloseRange * 1.5 then
        SmartManiac.AI.SetState(npc, STATE.STATE_CHASE)
        return
    end

    -- Face the target
    local dir = (target:GetPos() - npc:GetPos()):GetNormalized()
    local ang = dir:Angle()
    npc:SetAngles(Angle(0, ang.y, 0))

    -- Attack cooldown
    if CurTime() >= npc.sm_nextAttack then
        npc.sm_nextAttack = CurTime() + SmartManiac.Config.AttackCooldown

        -- Play attack animation
        npc:SetSchedule(SCHED_MELEE_ATTACK1)

        -- Deal damage
        timer.Simple(0.3, function()
            if not IsValid(npc) or not IsValid(target) then return end
            if npc:GetPos():Distance(target:GetPos()) <= SmartManiac.Config.CloseRange * 1.8 then
                local dmg = DamageInfo()
                dmg:SetAttacker(npc)
                dmg:SetInflictor(npc)
                dmg:SetDamage(SmartManiac.Config.AttackDamage)
                dmg:SetDamageType(DMG_SLASH)
                target:TakeDamageInfo(dmg)

                -- Blood effect
                local ef = EffectData()
                ef:SetOrigin(target:GetPos() + Vector(0, 0, 40))
                ef:SetScale(1)
                util.Effect("BloodImpact", ef)
            end
        end)

        -- Trigger a phrase
        if isfunction(npc.SayPhrase) then
            npc:SayPhrase("attack")
        end
    end
end

stateHandlers[STATE.STATE_LOST] = function(npc)
    -- Move to last known position
    if npc.sm_lastKnownPos then
        local dist = npc:GetPos():Distance(npc.sm_lastKnownPos)
        if dist > 80 then
            MoveToPos(npc, npc.sm_lastKnownPos)
        end
    end

    -- Can we re-acquire the target?
    local target = FindTarget(npc)
    if target then
        npc.sm_target = target
        npc.sm_lastKnownPos = target:GetPos()
        SmartManiac.AI.SetState(npc, STATE.STATE_CHASE)
        return
    end

    -- Check for any heard noise
    local heardTarget = FindHeardTarget(npc)
    if heardTarget then
        npc.sm_investigatePos = heardTarget:GetPos()
        SmartManiac.AI.SetState(npc, STATE.STATE_INVESTIGATE)
        return
    end

    -- Check voice events
    if npc.sm_heardVoice and #npc.sm_heardVoice > 0 then
        local latest = npc.sm_heardVoice[#npc.sm_heardVoice]
        if CurTime() - latest.time < 5 then
            npc.sm_investigatePos = latest.pos
            SmartManiac.AI.SetState(npc, STATE.STATE_INVESTIGATE)
            npc.sm_heardVoice = {}
            return
        end
    end

    -- Timeout: give up and go back to patrol
    if CurTime() - npc.sm_stateStart > SmartManiac.Config.LostTargetTime then
        if isfunction(npc.SayPhrase) then
            npc:SayPhrase("lost")
        end
        SmartManiac.AI.SetState(npc, STATE.STATE_PATROL)
    end
end

-- ============================================================
-- Main think entry point
-- ============================================================

--- Run one AI tick for the given NPC.
-- @param npc Entity
function SmartManiac.AI.Think(npc)
    if not IsValid(npc) or not npc:IsNPC() then return end

    local handler = stateHandlers[npc.sm_state]
    if handler then
        handler(npc)
    else
        SmartManiac.AI.SetState(npc, STATE.STATE_IDLE)
    end
end

--- Register a voice event heard by this NPC.
-- @param npc Entity
-- @param pos Vector Where the voice came from.
function SmartManiac.AI.OnVoiceHeard(npc, pos)
    if not IsValid(npc) then return end
    npc.sm_heardVoice = npc.sm_heardVoice or {}
    table.insert(npc.sm_heardVoice, { pos = pos, time = CurTime() })
    -- Keep only the last 5 entries
    while #npc.sm_heardVoice > 5 do
        table.remove(npc.sm_heardVoice, 1)
    end
end
