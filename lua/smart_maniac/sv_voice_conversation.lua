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
local PROACTIVE_COOLDOWN = 5
local PROACTIVE_MIN_INTERVAL = 15
local PROACTIVE_MAX_INTERVAL = 35
local PROACTIVE_RANGE = 800
local SPEAKING_SUPPRESS_TIME = 8

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

local CONTEXTUAL_SYSTEM_PROMPT = "Ты — жуткий маньяк-убийца в хоррор-игре. Игрок ТОЛЬКО ЧТО ГОВОРИЛ С ТОБОЙ через голосовой чат.\n"
    .. "Ты не разобрал точных слов, но слышал его голос. Ответь ему как будто ведёшь ДИАЛОГ.\n"
    .. "\n"
    .. "Правила:\n"
    .. "- РЕАГИРУЙ на то что игрок что-то сказал (он обращался к тебе!)\n"
    .. "- Можешь спросить 'Что ты сказал?', 'Повтори...', 'Я тебя слышу...'\n"
    .. "- Можешь ответить угрозой, издёвкой, чёрным юмором\n"
    .. "- Можешь сделать вид что понял: 'А, ты про это... хе-хе'\n"
    .. "- 10-25 слов\n"
    .. "- Грубая мужская манера\n"
    .. "- Учитывай ситуацию и историю разговора\n"
    .. "- Будь РАЗНООБРАЗНЫМ — не повторяй предыдущие фразы\n"
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
local responseCooldowns = {}   -- Cooldown for transcript-based responses
local voiceEventCooldowns = {} -- Cooldown for voice-event responses (player spoke but no transcript)
local proactiveCooldowns = {}  -- Separate cooldown for proactive speech (does NOT block responses)
local proactiveTimers = {}
local speakingSuppression = {} -- NPCs suppressed from proactive speech while player talks
local npcSpeakingUntil = {}   -- Global speaking lock: NPC is speaking/waiting for API response

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

--- speechType: "response" (replying to player), "proactive" (talking on own), "imitation" (mocking player)
local function BroadcastVoiceResponse(npc, phrase, speechType)
    phrase = CleanPhrase(phrase)
    if phrase == "" or not IsValid(npc) then return end
    speechType = speechType or "proactive"

    local npcIdx = npc:EntIndex()
    -- Lock this NPC from speaking for ~6 seconds (TTS playback duration estimate)
    npcSpeakingUntil[npcIdx] = CurTime() + 6

    net.Start("SmartManiac_Phrase")
        net.WriteEntity(npc)
        net.WriteString(phrase)
        net.WriteString(speechType)
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
    -- Voice responses use their own cooldown — NOT blocked by proactive speech
    if responseCooldowns[npcIdx] and CurTime() < responseCooldowns[npcIdx] then
        print("[Smart Maniac] HandleVoiceTranscript: NPC #" .. npcIdx .. " on response cooldown, skipping but saving transcript")
        AddToHistory(ply, npc, "user", transcript)
        return
    end
    responseCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    -- Suppress proactive speech for a while after responding to voice
    speakingSuppression[npcIdx] = CurTime() + SPEAKING_SUPPRESS_TIME

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

    local responseType = useImitation and "imitation" or "response"
    MakeAPICall(messages, 150, 0.95, function(phrase)
        if IsValid(npc) then
            AddToHistory(ply, npc, "assistant", phrase)
            BroadcastVoiceResponse(npc, phrase, responseType)
        end
    end)
end

--- Handle voice event: player spoke near a maniac (called when player STOPS speaking).
--- This is the PRIMARY voice response system — works without STT.
--- Uses its own cooldown so it doesn't block transcript responses if STT ever works.
function SmartManiac.VoiceConv.HandleVoiceEvent(ply, speakDuration)
    if not IsValid(ply) then return end
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local npc, dist = FindNearestManiac(ply, VOICE_CONV_RANGE)
    if not IsValid(npc) then return end

    local npcIdx = npc:EntIndex()

    -- Don't respond if NPC is already speaking or waiting for API response
    if npcSpeakingUntil[npcIdx] and CurTime() < npcSpeakingUntil[npcIdx] then
        print("[Smart Maniac] HandleVoiceEvent: NPC #" .. npcIdx .. " is currently speaking, skipping")
        return
    end

    -- Use voice event cooldown (separate from transcript and proactive cooldowns)
    if voiceEventCooldowns[npcIdx] and CurTime() < voiceEventCooldowns[npcIdx] then
        print("[Smart Maniac] HandleVoiceEvent: NPC #" .. npcIdx .. " on voice event cooldown")
        return
    end
    -- Don't respond if we already got a real transcript for this speech (STT worked)
    if responseCooldowns[npcIdx] and CurTime() < responseCooldowns[npcIdx] then
        print("[Smart Maniac] HandleVoiceEvent: NPC #" .. npcIdx .. " already responded via transcript")
        return
    end

    voiceEventCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN
    -- Lock NPC from ALL speech while we wait for API response + playback
    npcSpeakingUntil[npcIdx] = CurTime() + 12
    -- Suppress proactive speech after responding
    speakingSuppression[npcIdx] = CurTime() + SPEAKING_SUPPRESS_TIME

    print("[Smart Maniac] HandleVoiceEvent: " .. ply:Nick() .. " spoke for " .. string.format("%.1f", speakDuration) .. "s near NPC #" .. npcIdx .. " (dist=" .. math.Round(dist) .. ")")

    local context = GetGameContext(npc, ply)
    local durationHint = ""
    if speakDuration > 5 then
        durationHint = " Игрок говорил долго (" .. math.Round(speakDuration) .. " сек) — он явно хочет поговорить."
    elseif speakDuration > 2 then
        durationHint = " Игрок сказал пару фраз."
    else
        durationHint = " Игрок сказал что-то короткое."
    end

    local messages = {
        { role = "system", content = CONTEXTUAL_SYSTEM_PROMPT },
    }

    -- Add conversation history for continuity
    local history = GetHistory(ply, npc)
    for _, msg in ipairs(history) do
        table.insert(messages, { role = msg.role, content = msg.content })
    end

    table.insert(messages, { role = "user", content = context .. durationHint .. " Игрок только что говорил с тобой. Ответь ему." })

    MakeAPICall(messages, 120, 0.95, function(phrase)
        if IsValid(npc) and IsValid(ply) then
            AddToHistory(ply, npc, "user", "[игрок говорил голосом]")
            AddToHistory(ply, npc, "assistant", phrase)
            BroadcastVoiceResponse(npc, phrase, "response")
            print("[Smart Maniac] Voice event response: " .. phrase)
        end
    end)
end

--- Handle contextual voice (legacy, kept for compatibility).
function SmartManiac.VoiceConv.HandleContextualVoice(npc, ply)
    if not IsValid(npc) or not IsValid(ply) then return end
    SmartManiac.VoiceConv.HandleVoiceEvent(ply, 2.0)
end

--- Proactive speaking: maniac talks on his own near players.
function SmartManiac.VoiceConv.ProactiveSpeech(npc)
    if not IsValid(npc) then return end
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local npcIdx = npc:EntIndex()

    -- Don't speak proactively if NPC is currently speaking or waiting for API response
    if npcSpeakingUntil[npcIdx] and CurTime() < npcSpeakingUntil[npcIdx] then return end

    -- Don't speak proactively if suppressed (player recently spoke / NPC just responded)
    if speakingSuppression[npcIdx] and CurTime() < speakingSuppression[npcIdx] then return end

    -- Don't speak proactively if ANY player nearby is currently speaking (don't interrupt)
    if SmartManiac.Voice and SmartManiac.Voice.SpeakingPlayers then
        for ply, _ in pairs(SmartManiac.Voice.SpeakingPlayers) do
            if IsValid(ply) and ply:Alive() then
                local dist = npc:GetPos():Distance(ply:GetPos())
                if dist <= VOICE_CONV_RANGE then
                    return -- Player is speaking nearby, don't interrupt
                end
            end
        end
    end

    -- Use proactive cooldown (separate from response cooldown)
    if proactiveCooldowns[npcIdx] and CurTime() < proactiveCooldowns[npcIdx] then return end

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

    proactiveCooldowns[npcIdx] = CurTime() + PROACTIVE_COOLDOWN
    -- Lock NPC from other speech while API call is in flight
    npcSpeakingUntil[npcIdx] = CurTime() + 10

    local context = GetGameContext(npc, nearestPly)
    local messages = {
        { role = "system", content = PROACTIVE_SYSTEM_PROMPT },
        { role = "user", content = context .. ". Скажи что-нибудь зловещее." },
    }

    MakeAPICall(messages, 80, 1.0, function(phrase)
        if IsValid(npc) then
            BroadcastVoiceResponse(npc, phrase, "proactive")
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
    for idx, _ in pairs(responseCooldowns) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            responseCooldowns[idx] = nil
        end
    end
    for idx, _ in pairs(voiceEventCooldowns) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            voiceEventCooldowns[idx] = nil
        end
    end
    for idx, _ in pairs(proactiveCooldowns) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            proactiveCooldowns[idx] = nil
        end
    end
    for idx, _ in pairs(speakingSuppression) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            speakingSuppression[idx] = nil
        end
    end
    for idx, _ in pairs(npcSpeakingUntil) do
        local ent = Entity(idx)
        if not IsValid(ent) then
            npcSpeakingUntil[idx] = nil
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
