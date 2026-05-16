--[[
    Smart Maniac NPC - Voice Conversation System (Server)
    Handles voice transcriptions from clients and generates AI responses.
    Responds specifically to what the player said with natural dialogue.
]]

SmartManiac = SmartManiac or {}
SmartManiac.VoiceConv = SmartManiac.VoiceConv or {}

local VOICE_CONV_RANGE = 1500
local MAX_HISTORY = 10

local VOICE_SYSTEM_PROMPT = "Ты — жуткий маньяк-убийца в хоррор-игре. Игрок говорит с тобой через голосовой чат.\n\nГЛАВНОЕ ПРАВИЛО: Ты ВСЕГДА отвечаешь КОНКРЕТНО на то что сказал игрок. Если он задал вопрос — ответь на вопрос. Если он что-то сказал — отреагируй на его слова. Это живой диалог.\n\nТвой характер:\n- Грубый, хладнокровный мужик-убийца\n- Говоришь коротко но по делу (15-30 слов)\n- Можешь пугать, угрожать, шутить чёрным юмором\n- Иногда саркастичен\n- Знаешь что ты в игре но играешь свою роль\n- Можешь намекать что знаешь где игрок\n\nПравила ответа:\n- ОТВЕЧАЙ на реплику игрока — это ДИАЛОГ а не монолог\n- 15-30 слов максимум\n- ТОЛЬКО русский язык\n- Без кавычек в ответе\n- Будь непредсказуемым — не повторяй одно и то же"

local CONTEXTUAL_SYSTEM_PROMPT = "Ты — маньяк-убийца в хоррор-игре. Ты слышишь голос игрока рядом но не разбираешь слов.\n\nСкажи жуткую фразу реагируя на голос:\n- 10-20 слов\n- Грубая мужская манера\n- Угрожающе и зловеще\n- Учитывай ситуацию (что ты делаешь сейчас)\n- ТОЛЬКО русский язык\n- Без кавычек"

-- Per-player-NPC conversation history
local conversationHistory = {}

-- Cooldowns per NPC
local npcCooldowns = {}
local RESPONSE_COOLDOWN = 4

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
    local state = npc:GetManiacState and npc:GetManiacState() or 0
    local stateNames = {
        [0] = "стоишь без дела",
        [1] = "патрулируешь территорию",
        [2] = "идёшь на звук",
        [3] = "гонишься за игроком",
        [4] = "атакуешь",
        [5] = "ищешь потерянную цель",
    }
    local stateName = stateNames[state] or "неизвестно"
    local dist = IsValid(ply) and math.Round(npc:GetPos():Distance(ply:GetPos())) or 0
    local health = npc:Health()
    return string.format("Ты сейчас: %s. Расстояние до игрока: %d. Твоё здоровье: %d", stateName, dist, health)
end

local function BroadcastVoiceResponse(npc, phrase)
    if not IsValid(npc) or not phrase or phrase == "" then return end
    phrase = string.gsub(phrase, '^"', "")
    phrase = string.gsub(phrase, '"$', "")
    phrase = string.Trim(phrase)
    if phrase == "" then return end
    if #phrase > 300 then
        phrase = string.sub(phrase, 1, 300)
    end
    net.Start("SmartManiac_Phrase")
        net.WriteEntity(npc)
        net.WriteString(phrase)
    net.Broadcast()
    local target = npc:GetManiacTarget and npc:GetManiacTarget()
    if IsValid(target) then
        npc:SetEyeTarget(target:EyePos())
    end
    print("[Smart Maniac] Voice response: " .. phrase)
end

function SmartManiac.VoiceConv.HandleVoiceTranscript(ply, transcript)
    if not IsValid(ply) then return end
    if not transcript or transcript == "" then return end
    if not GetConVar("sm_maniac_voice_ai"):GetBool() then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end
    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local npc, dist = FindNearestManiac(ply, VOICE_CONV_RANGE)
    if not IsValid(npc) then return end

    local npcIdx = npc:EntIndex()
    if npcCooldowns[npcIdx] and CurTime() < npcCooldowns[npcIdx] then return end
    npcCooldowns[npcIdx] = CurTime() + RESPONSE_COOLDOWN

    AddToHistory(ply, npc, "user", transcript)

    local context = GetGameContext(npc, ply)
    local messages = {
        { role = "system", content = VOICE_SYSTEM_PROMPT .. "\n\n" .. context },
    }
    local history = GetHistory(ply, npc)
    for _, msg in ipairs(history) do
        table.insert(messages, { role = msg.role, content = msg.content })
    end

    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()
    local body = util.TableToJSON({
        model = model,
        messages = messages,
        max_tokens = 150,
        temperature = 0.95,
    })

    print("[Smart Maniac] Processing voice from " .. ply:Nick() .. ": " .. transcript)

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
    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()
    local body = util.TableToJSON({
        model = model,
        messages = {
            { role = "system", content = CONTEXTUAL_SYSTEM_PROMPT },
            { role = "user", content = context .. ". Ты слышишь голос игрока рядом." },
        },
        max_tokens = 100,
        temperature = 0.95,
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
            if IsValid(npc) and isfunction(npc.SayPhrase) then
                npc:SayPhrase("investigate")
            end
        end,
    })
end

net.Receive("SmartManiac_VoiceTranscript", function(len, ply)
    if not IsValid(ply) then return end
    local transcript = net.ReadString()
    if not transcript or transcript == "" then return end
    SmartManiac.VoiceConv.HandleVoiceTranscript(ply, transcript)
end)

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
end)

print("[Smart Maniac] Voice conversation module loaded (improved prompts).")
