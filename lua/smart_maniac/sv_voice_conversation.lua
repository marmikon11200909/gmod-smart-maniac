--[[
    Smart Maniac NPC - Voice Conversation System (Server) - MAXIMUM FIX
    
    Handles voice transcriptions from clients and generates AI responses.
    Features:
    - Responds specifically to what the player said (direct dialogue)
    - Voice imitation: can mock/repeat player words sarcastically
    - Proactive speaking: maniac talks on his own near players
    - Per-player conversation history for coherent dialogue
    - Game context injection (state, distance, health)
    - Robust error handling and logging
]]

SmartManiac = SmartManiac or {}
SmartManiac.VoiceConv = SmartManiac.VoiceConv or {}

local VOICE_CONV_RANGE = 1500
local MAX_HISTORY = 12
local RESPONSE_COOLDOWN = 3
local PROACTIVE_MIN_INTERVAL = 8
local PROACTIVE_MAX_INTERVAL = 20
local PROACTIVE_RANGE = 800

local VOICE_SYSTEM_PROMPT = "Ты — жуткий маньяк-убийца в хоррор-игре. Игрок говорит с тобой через голосовой чат.\n"
    .. "\n"
    .. "ГЛАВНОЕ ПРАВИЛО: Ты ВСЕГДА отвечаешь КОНКРЕТНО на то что сказал игрок.\n"
    .. "Если он задал вопрос — ответь на вопрос. Если он что-то сказал — отреагируй ИМЕННО на его слова.\n"
    .. "Если он сказал привет — поприветствуй его зловеще. Если спросил кто ты — расскажи.\n"
    .. "Если он повторяет одно и то же — заметь это и отреагируй.\n"
    .. "\n"
    .. "Твой характер:\n"
    .. "- Грубый, хладнокровный мужик-убийца\n"
    .. "- Говоришь коротко но по делу (10-30 слов)\n"
    .. "- Можешь пугать, угрожать, шутить чёрным юмором\n"
    .. "- Иногда саркастичен и передразниваешь игрока\n"
    .. "- Можешь ПОВТОРИТЬ слова игрока насмешливо (имитация голоса)\n"
    .. "- Знаешь что ты в игре но играешь свою роль\n"
    .. "- Можешь намекать что знаешь где игрок\n"
    .. "\n"
    .. "Правила ответа:\n"
    .. "- ОТВЕЧАЙ на реплику игрока — это ДИАЛОГ а не монолог\n"
    .. "- 10-30 слов максимум\n"
    .. "- ТОЛЬКО русский язык\n"
    .. "- Без кавычек в ответе\n"
    .. "- Будь непредсказуемым — не повторяй одно и то же\n"
    .. "- Иногда передразнивай игрока, повторяя его слова с насмешкой"

local CONTEXTUAL_SYSTEM_PROMPT = "Ты — маньяк-убийца в хоррор-игре. Ты слышишь голос игрока рядом но не разбираешь слов.\n"
    .. "Скажи жуткую фразу реагируя на голос:\n"
    .. "- 10-20 слов\n"
    .. "- Грубая мужская манера\n"
    .. "- Угрожающе и зловеще\n"
    .. "- Учитывай ситуацию (что ты делаешь сейчас)\n"
    .. "- ТОЛЬКО русский язык\n"
    .. "- Без кавычек"

local PROACTIVE_SYSTEM_PROMPT = "Ты — маньяк-убийца в хоррор-игре. Ты бродишь рядом с игроком.\n"
    .. "Скажи что-нибудь зловещее БЕЗ повода — просто потому что ты маньяк:\n"
    .. "- 5-20 слов\n"
    .. "- Можешь бормотать себе под нос\n"
    .. "- Можешь обращаться к игроку\n"
    .. "- Можешь напевать жутко\n"
    .. "- Можешь угрожать, шутить, пугать\n"
    .. "- Будь РАЗНООБРАЗНЫМ и НЕПРЕДСКАЗУЕМЫМ\n"
    .. "- ТОЛЬКО русский язык\n"
    .. "- Без кавычек"

local IMITATION_SYSTEM_PROMPT = "Ты — маньяк-убийца. Игрок только что сказал тебе фразу.\n"
    .. "ПЕРЕДРАЗНИ его — повтори его слова НАСМЕШЛИВО и ЗЛОВЕЩЕ:\n"
    .. "- Повтори часть его фразы с насмешкой\n"
    .. "- Добавь угрозу или издёвку\n"
    .. "- 10-25 слов\n"
    .. "- Грубая мужская манера\n"
    .. "- ТОЛЬКО русский язык\n"
    .. "- Без кавычек"

-- Per-player-NPC conversation history
local conversationHistory = {}
local npcCooldowns = {}
local proactiveTimers = {}

local function GetConvKey(ply, npc)
    if not IsValid(ply) or not IsValid(npc) then return nil end
    return ply:SteamID64() .. "_" .. npc:EntIndex()
end

local function GetHistory(ply, npc)
    local key = GetConvKey(ply, npc)
    if not key then return {} end
    if not conversationHistory[key] then
        conversationHistory[key] = {}
    end
    return conversationHistory[key]
end

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
    while #conversationHistory[key] > MAX_HISTORY do
        table.remove(conversationHistory[key], 1)
    end
end

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

local function GetGameContext(npc, ply)
    if not IsValid(npc) then return "" end
    local state = npc.GetManiacState and npc:GetManiacState() or 0
    local stateNames = {
        [0] = "стоишь без дела",
        [1] = "патрулируешь территорию",
        [2] = "идёшь на звук",
        [3] = "гонишься за игроком",
        [4] = "атакуешь",
        [5] = "ищешь потерянную цель",
    }
    local stateName = stateNames[state] or "бродишь"
    local dist = IsValid(ply) and math.Round(npc:GetPos():Distance(ply:GetPos())) or 0
    local health = npc:Health()
    return string.format("Ты сейчас: %s. Расстояние до игрока: %d. Твоё здоровье: %d", stateName, dist, health)
end

local function CleanPhrase(phrase)
    if not phrase or phrase == "" then return "" end
    phrase = string.gsub(phrase, '^\"*', "")
    phrase = string.gsub(phrase, '\"*$', "")
    phrase = string.gsub(phrase, "^\'*", "")
    phrase = string.gsub(phrase, "\'*$", "")
    phrase = string.Trim(phrase)
    if #phrase > 300 then
        phrase = string.sub(phrase, 1, 300)
    end
    return phrase
end

local function BroadcastVoiceResponse(npc, phrase)
    phrase = CleanPhrase(phrase)
    if phrase == "" or not IsValid(npc) then return end

    net.Start("SmartManiac_Phrase")
        net.WriteEntity(npc)
        net.WriteString(phrase)
    net.Broadcast()

    -- Look at target player
    local target = npc.GetManiacTarget and npc:GetManiacTarget()
    if IsValid(target) then
        npc:SetEyeTarget(target:EyePos())
    end

    -- Also play a sound effect for atmosphere
    if SmartManiac.Sound and SmartManiac.Sound.PlaySound then
        SmartManiac.Sound.PlaySound(npc, "idle")
    end

    print("[Smart Maniac] Voice response: " .. phrase)
end

local function MakeAPICall(messages, maxTokens, temperature, callback)
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    local body = util.TableToJSON({
        model = model,
        messages = messages,
        max_tokens = maxTokens or 150,
        temperature = temperature or 0.95,
    })

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. apiKey,
    }

    -- Use SmartManiac.API.Request which auto-falls back to DHTML relay on SSL errors
    SmartManiac.API.Request(apiUrl, "POST", headers, body,
        function(code, responseBody)
            if code ~= 200 then
                print("[Smart Maniac] Voice AI HTTP error: " .. tostring(code))
                print("[Smart Maniac] Response: " .. string.sub(tostring(responseBody), 1, 200))
                return
            end
            local data = util.JSONToTable(responseBody)
            if data and data.choices and data.choices[1] then
                local phrase = data.choices[1].message and data.choices[1].message.content or ""
                phrase = CleanPhrase(phrase)
                if phrase ~= "" and callback then
                    callback(phrase)
                end
            end
        end,
        function(err)
            print("[Smart Maniac] Voice AI request failed: " .. tostring(err))
        end
    )
end

--- Handle a voice transcript from a player (main conversation handler).
function SmartManiac.VoiceConv.HandleVoiceTranscript(ply, transcript)
    if not IsValid(ply) then
        print("[Smart Maniac] HandleVoiceTranscript: invalid player")
        return
    end
    if not transcript or transcript == "" then
        print("[Smart Maniac] HandleVoiceTranscript: empty transcript")
        return
    end
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then
        print("[Smart Maniac] HandleVoiceTranscript: voice AI disabled (sm_maniac_voice_ai 0)")
        return
    end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then
        print("[Smart Maniac] HandleVoiceTranscript: OpenAI disabled (sm_maniac_openai_enabled 0)")
        return
    end
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then
        print("[Smart Maniac] HandleVoiceTranscript: no API key set (sm_maniac_openai_key)")
        return
    end

    local npc, dist = FindNearestManiac(ply, VOICE_CONV_RANGE)
    if not IsValid(npc) then
        print("[Smart Maniac] HandleVoiceTranscript: no maniac within " .. VOICE_CONV_RANGE .. " units")
        return
    end

    local npcIdx = npc:EntIndex()
    if npcCooldowns[npcIdx] and CurTime() < npcCooldowns[npcIdx] then
        print("[Smart Maniac] HandleVoiceTranscript: NPC #" .. npcIdx .. " on cooldown, skipping response but saving transcript")
        AddToHistory(ply, npc, "user", transcript)
        return
    end
    npcCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    AddToHistory(ply, npc, "user", transcript)
    print("[Smart Maniac] Processing voice from " .. ply:Nick() .. ": " .. transcript .. " (NPC #" .. npcIdx .. ", dist=" .. math.Round(dist) .. ")")

    -- Randomly choose between normal response (70%) and imitation/mockery (30%)
    local useImitation = math.random() < 0.3
    local systemPrompt = useImitation and IMITATION_SYSTEM_PROMPT or VOICE_SYSTEM_PROMPT

    local context = GetGameContext(npc, ply)
    local messages = {
        { role = "system", content = systemPrompt .. "\n\n" .. context },
    }

    -- Add conversation history
    local history = GetHistory(ply, npc)
    for _, msg in ipairs(history) do
        table.insert(messages, { role = msg.role, content = msg.content })
    end

    MakeAPICall(messages, 150, 0.95, function(phrase)
        if IsValid(npc) then
            AddToHistory(ply, npc, "assistant", phrase)
            BroadcastVoiceResponse(npc, phrase)
        end
    end)
end

--- Handle contextual voice (player is talking but STT unavailable).
function SmartManiac.VoiceConv.HandleContextualVoice(npc, ply)
    if not IsValid(npc) or not IsValid(ply) then return end
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then
        if isfunction(npc.SayPhrase) then
            npc:SayPhrase("investigate")
        end
        return
    end

    local npcIdx = npc:EntIndex()
    if npcCooldowns[npcIdx] and CurTime() < npcCooldowns[npcIdx] then return end
    npcCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    local context = GetGameContext(npc, ply)
    local messages = {
        { role = "system", content = CONTEXTUAL_SYSTEM_PROMPT },
        { role = "user", content = context .. ". Ты слышишь голос игрока рядом." },
    }

    MakeAPICall(messages, 100, 0.95, function(phrase)
        if IsValid(npc) then
            BroadcastVoiceResponse(npc, phrase)
        end
    end)
end

--- Proactive speaking: maniac talks on his own near players.
function SmartManiac.VoiceConv.ProactiveSpeech(npc)
    if not IsValid(npc) then return end
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local npcIdx = npc:EntIndex()
    if npcCooldowns[npcIdx] and CurTime() < npcCooldowns[npcIdx] then return end

    -- Find nearest player within proactive range
    local nearestPly = nil
    local nearestDist = PROACTIVE_RANGE + 1
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local dist = npc:GetPos():Distance(ply:GetPos())
            if dist < nearestDist then
                nearestDist = dist
                nearestPly = ply
            end
        end
    end

    if not IsValid(nearestPly) then return end

    npcCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    local context = GetGameContext(npc, nearestPly)
    local messages = {
        { role = "system", content = PROACTIVE_SYSTEM_PROMPT },
        { role = "user", content = context .. ". Скажи что-нибудь зловещее." },
    }

    MakeAPICall(messages, 80, 1.0, function(phrase)
        if IsValid(npc) then
            BroadcastVoiceResponse(npc, phrase)
        end
    end)
end

-- Receive voice transcript from client
net.Receive("SmartManiac_VoiceTranscript", function(len, ply)
    if not IsValid(ply) then return end
    local transcript = net.ReadString()
    if not transcript or transcript == "" then
        print("[Smart Maniac] Empty transcript received from " .. ply:Nick() .. ", ignoring")
        return
    end
    print("[Smart Maniac] >>> TRANSCRIPT from " .. ply:Nick() .. ": " .. transcript)
    SmartManiac.VoiceConv.HandleVoiceTranscript(ply, transcript)
end)

-- Proactive speaking timer: periodically make maniacs say things
timer.Create("SmartManiac_ProactiveSpeech", 5, 0, function()
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    for _, npc in ipairs(ents.FindByClass("npc_smart_maniac")) do
        if not IsValid(npc) or npc:Health() <= 0 then continue end

        local npcIdx = npc:EntIndex()
        if not proactiveTimers[npcIdx] then
            proactiveTimers[npcIdx] = CurTime() + math.random(PROACTIVE_MIN_INTERVAL, PROACTIVE_MAX_INTERVAL)
        end

        if CurTime() >= proactiveTimers[npcIdx] then
            proactiveTimers[npcIdx] = CurTime() + math.random(PROACTIVE_MIN_INTERVAL, PROACTIVE_MAX_INTERVAL)
            SmartManiac.VoiceConv.ProactiveSpeech(npc)
        end
    end
end)

-- Cleanup on player disconnect
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

-- Periodic cleanup of stale data
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
    for idx, _ in pairs(npcCooldowns) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            npcCooldowns[idx] = nil
        end
    end
    for idx, _ in pairs(proactiveTimers) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            proactiveTimers[idx] = nil
        end
    end
end)

print("[Smart Maniac] Voice conversation module loaded (improved prompts + proactive speech + imitation).")
