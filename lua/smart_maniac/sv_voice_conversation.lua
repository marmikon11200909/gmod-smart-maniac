--[[
    Smart Maniac NPC - Voice Conversation System (Server)
    Handles voice transcriptions from clients and generates AI responses.
    When a player speaks via voice chat and their speech is transcribed,
    the nearest maniac NPC generates an AI response and speaks it back.

    Also handles contextual responses when STT is unavailable —
    the maniac reacts to voice detection with context-aware AI phrases.
]]

SmartManiac = SmartManiac or {}
SmartManiac.VoiceConv = SmartManiac.VoiceConv or {}

local VOICE_CONV_RANGE = 1500
local MAX_HISTORY = 10

local VOICE_SYSTEM_PROMPT = [[Ты — жуткий маньяк-убийца в хоррор-игре Garry's Mod. Игрок разговаривает с тобой через голосовой чат.
Правила:
- Отвечай на реплику игрока как настоящий маньяк-убийца с грубым мужским характером
- Максимум 20 слов в ответе
- Будь угрожающим, пугающим, зловещим и дерзким
- Используй грубую мужскую манеру речи — ты жёсткий, хладнокровный убийца
- Можешь использовать чёрный юмор и сарказм
- Иногда намекай что знаешь где игрок прячется
- ВСЕГДА говори ТОЛЬКО на русском языке
- Не используй кавычки в ответе
- Реагируй на то что сказал игрок — это живой разговор]]

local CONTEXTUAL_SYSTEM_PROMPT = [[Ты — жуткий маньяк-убийца в хоррор-игре Garry's Mod. Ты слышишь голос игрока рядом.
Правила:
- Скажи короткую жуткую фразу, реагируя на то что слышишь голос
- Максимум 15 слов
- Будь угрожающим и зловещим с грубой мужской манерой
- Учитывай текущую ситуацию (патрулируешь, гонишься, ищешь и т.д.)
- ВСЕГДА говори ТОЛЬКО на русском языке
- Не используй кавычки]]

-- Per-player-NPC conversation history
local conversationHistory = {}

-- Cooldowns per NPC to avoid spam
local npcCooldowns = {}
local RESPONSE_COOLDOWN = 2

--- Get a unique key for a player-NPC conversation pair.
local function GetConvKey(ply, npc)
    if not IsValid(ply) or not IsValid(npc) then return nil end
    return ply:SteamID64() .. "_" .. npc:EntIndex()
end

--- Get or create conversation history for a player-NPC pair.
local function GetHistory(ply, npc)
    local key = GetConvKey(ply, npc)
    if not key then return {} end

    if not conversationHistory[key] then
        conversationHistory[key] = {}
    end

    return conversationHistory[key]
end

--- Add a message to conversation history.
local function AddToHistory(ply, npc, role, content)
    local key = GetConvKey(ply, npc)
    if not key then return end

    if not conversationHistory[key] then
        conversationHistory[key] = {}
    end

    table.insert(conversationHistory[key], {
        role = role,
        content = content,
    })

    -- Trim history if too long
    while #conversationHistory[key] > MAX_HISTORY do
        table.remove(conversationHistory[key], 1)
    end
end

--- Find the nearest maniac NPC to a player within range.
local function FindNearestManiac(ply, range)
    if not IsValid(ply) then return nil end

    local bestNPC = nil
    local bestDist = range + 1

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if IsValid(npc) and npc:Health() > 0 then
            local dist = npc:GetPos():Distance(ply:GetPos())
            if dist < bestDist then
                bestDist = dist
                bestNPC = npc
            end
        end
    end

    return bestNPC, bestDist
end

--- Get game context string for AI prompts.
local function GetGameContext(npc, ply)
    if not IsValid(npc) then return "" end

    local state = npc:GetManiacState and npc:GetManiacState() or 0
    local stateNames = {
        [0] = "idle",
        [1] = "patrolling",
        [2] = "investigating a sound",
        [3] = "chasing a player",
        [4] = "attacking",
        [5] = "searching for lost target",
    }

    local stateName = stateNames[state] or "unknown"
    local dist = IsValid(ply) and math.Round(npc:GetPos():Distance(ply:GetPos())) or 0
    local health = npc:Health()

    return string.format("State: %s, Distance to player: %d units, Health: %d", stateName, dist, health)
end

--- Send AI response to all clients for TTS playback.
local function BroadcastVoiceResponse(npc, phrase)
    if not IsValid(npc) or not phrase or phrase == "" then return end

    -- Strip quotes
    phrase = string.gsub(phrase, '^"', "")
    phrase = string.gsub(phrase, '"$', "")
    phrase = string.Trim(phrase)

    if phrase == "" then return end

    -- Limit length
    if #phrase > 200 then
        phrase = string.sub(phrase, 1, 200)
    end

    -- Send phrase via existing network message
    net.Start("SmartManiac_Phrase")
        net.WriteEntity(npc)
        net.WriteString(phrase)
    net.Broadcast()

    -- Make NPC look at nearest player
    local target = npc:GetManiacTarget and npc:GetManiacTarget()
    if IsValid(target) then
        npc:SetEyeTarget(target:EyePos())
    end

    print("[Smart Maniac] Voice response: " .. phrase)
end

--- Handle a voice transcript from a player — generate AI response.
function SmartManiac.VoiceConv.HandleVoiceTranscript(ply, transcript)
    if not IsValid(ply) then return end
    if not transcript or transcript == "" then return end

    -- Check if voice AI is enabled
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    -- Find nearest maniac
    local npc, dist = FindNearestManiac(ply, VOICE_CONV_RANGE)
    if not IsValid(npc) then return end

    -- Check cooldown
    local npcIdx = npc:EntIndex()
    if npcCooldowns[npcIdx] and CurTime() < npcCooldowns[npcIdx] then return end
    npcCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    -- Add player message to history
    AddToHistory(ply, npc, "user", transcript)

    -- Build messages for API
    local messages = {
        { role = "system", content = VOICE_SYSTEM_PROMPT .. "\n\nИгровой контекст: " .. GetGameContext(npc, ply) },
    }

    -- Add conversation history
    local history = GetHistory(ply, npc)
    for _, msg in ipairs(history) do
        table.insert(messages, { role = msg.role, content = msg.content })
    end

    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    local body = util.TableToJSON({
        model = model,
        messages = messages,
        max_tokens = 100,
        temperature = 0.9,
    })

    print("[Smart Maniac] Processing voice transcript from " .. ply:Nick() .. ": " .. transcript)

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
            if code ~= 200 then
                print("[Smart Maniac] Voice AI HTTP error: " .. tostring(code))
                return
            end

            local data = util.JSONToTable(responseBody)
            if data and data.choices and data.choices[1] then
                local phrase = data.choices[1].message and data.choices[1].message.content or ""
                phrase = string.Trim(phrase)

                if phrase ~= "" and IsValid(npc) then
                    AddToHistory(ply, npc, "assistant", phrase)
                    BroadcastVoiceResponse(npc, phrase)
                end
            end
        end,
        failed = function(err)
            print("[Smart Maniac] Voice AI request failed: " .. tostring(err))
        end,
    })
end

--- Handle contextual voice response (when STT is unavailable).
-- Generates an AI response based on game context when a player uses voice chat nearby.
function SmartManiac.VoiceConv.HandleContextualVoice(npc, ply)
    if not IsValid(npc) or not IsValid(ply) then return end

    -- Check if voice AI is enabled
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then
        -- Fallback to built-in phrase system
        if isfunction(npc.SayPhrase) then
            npc:SayPhrase("investigate")
        end
        return
    end

    -- Check cooldown
    local npcIdx = npc:EntIndex()
    if npcCooldowns[npcIdx] and CurTime() < npcCooldowns[npcIdx] then return end
    npcCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    local context = GetGameContext(npc, ply)
    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    local body = util.TableToJSON({
        model = model,
        messages = {
            { role = "system", content = CONTEXTUAL_SYSTEM_PROMPT },
            { role = "user", content = "Контекст: " .. context .. ". Ты слышишь голос игрока. Скажи что-нибудь жуткое." },
        },
        max_tokens = 80,
        temperature = 0.9,
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
            if code ~= 200 then return end

            local data = util.JSONToTable(responseBody)
            if data and data.choices and data.choices[1] then
                local phrase = data.choices[1].message and data.choices[1].message.content or ""
                phrase = string.Trim(phrase)

                if phrase ~= "" and IsValid(npc) then
                    BroadcastVoiceResponse(npc, phrase)
                end
            end
        end,
        failed = function(err)
            print("[Smart Maniac] Contextual voice AI failed: " .. tostring(err))
            -- Fallback to built-in phrases
            if IsValid(npc) and isfunction(npc.SayPhrase) then
                npc:SayPhrase("investigate")
            end
        end,
    })
end

--- Receive voice transcripts from clients.
net.Receive("SmartManiac_VoiceTranscript", function(len, ply)
    if not IsValid(ply) then return end

    local transcript = net.ReadString()
    if not transcript or transcript == "" then return end

    SmartManiac.VoiceConv.HandleVoiceTranscript(ply, transcript)
end)

--- Cleanup conversation history when a player disconnects.
hook.Add("PlayerDisconnected", "SmartManiac_VoiceConvCleanup", function(ply)
    if not IsValid(ply) then return end
    local sid = ply:SteamID64()
    if not sid then return end

    for key, _ in pairs(conversationHistory) do
        if string.StartWith(key, sid .. "_") then
            conversationHistory[key] = nil
        end
    end
end)

--- Periodic cleanup of stale conversation entries.
timer.Create("SmartManiac_VoiceConvCleanup", 60, 0, function()
    for key, _ in pairs(conversationHistory) do
        local parts = string.Explode("_", key)
        if #parts >= 2 then
            local entIdx = tonumber(parts[2])
            if entIdx then
                local ent = Entity(entIdx)
                if not IsValid(ent) then
                    conversationHistory[key] = nil
                end
            end
        end
    end

    -- Clean up NPC cooldowns
    for idx, _ in pairs(npcCooldowns) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            npcCooldowns[idx] = nil
        end
    end
end)

print("[Smart Maniac] Voice conversation module loaded.")
