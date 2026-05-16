--[[
    Smart Maniac NPC - Conversation System
    Allows players to talk to the maniac via text chat.
    When a player types in chat near a maniac NPC, the message is sent
    to the AI which generates a contextual response as the maniac character.
    Maintains a short conversation history per NPC for coherent dialogue.
]]

SmartManiac = SmartManiac or {}
SmartManiac.Conversation = SmartManiac.Conversation or {}

local CONVERSATION_RANGE = 1500
local MAX_HISTORY = 8

local CONV_SYSTEM_PROMPT = [[Ты — жуткий маньяк в хоррор-игре. Игрок пытается с тобой разговаривать.
Правила:
- Отвечай на реплику игрока как настоящий маньяк-убийца
- Максимум 15 слов в ответе
- Будь угрожающим, пугающим и зловещим
- Используй чёрный юмор и сарказм
- Можешь реагировать на то, что сказал игрок — отвечай по смыслу
- Если игрок просит пощады — издевайся
- Если игрок угрожает — смейся над ним
- Если игрок задаёт вопрос — отвечай загадочно и жутко
- ВСЕГДА говори ТОЛЬКО на русском языке
- Не используй кавычки в ответе
- Ты — персонаж, оставайся в роли маньяка]]

--- Find the nearest maniac NPC to a player within conversation range.
-- @param ply Player
-- @return Entity|nil  The nearest maniac or nil.
local function FindNearestManiac(ply)
    if not IsValid(ply) then return nil end

    local maniacs = ents.FindByClass("npc_smart_maniac")
    local best = nil
    local bestDist = math.huge

    for _, maniac in ipairs(maniacs) do
        if IsValid(maniac) and maniac:Health() > 0 then
            local dist = maniac:GetPos():Distance(ply:GetPos())
            if dist <= CONVERSATION_RANGE and dist < bestDist then
                bestDist = dist
                best = maniac
            end
        end
    end

    return best
end

--- Get or create conversation history for an NPC.
-- @param npc Entity
-- @return table  Array of {role, content} message objects.
local function GetHistory(npc)
    npc.sm_convHistory = npc.sm_convHistory or {}
    return npc.sm_convHistory
end

--- Add a message to the conversation history.
-- @param npc Entity
-- @param role string  "user" or "assistant"
-- @param content string
local function AddToHistory(npc, role, content)
    local history = GetHistory(npc)
    table.insert(history, { role = role, content = content })

    while #history > MAX_HISTORY do
        table.remove(history, 1)
    end
end

--- Send a player's chat message to the AI and have the maniac respond.
-- @param npc Entity  The maniac NPC.
-- @param ply Player  The player who spoke.
-- @param text string  What the player said.
function SmartManiac.Conversation.HandleChat(npc, ply, text)
    if not IsValid(npc) or not IsValid(ply) then return end
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    AddToHistory(npc, "user", text)

    local messages = {
        { role = "system", content = CONV_SYSTEM_PROMPT },
    }

    for _, msg in ipairs(GetHistory(npc)) do
        table.insert(messages, { role = msg.role, content = msg.content })
    end

    local body = util.TableToJSON({
        model = model,
        messages = messages,
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
            if code ~= 200 then
                print("[Smart Maniac] Conversation HTTP error: " .. tostring(code))
                return
            end

            local data = util.JSONToTable(responseBody)
            if data and data.choices and data.choices[1] then
                local reply = data.choices[1].message and data.choices[1].message.content or ""
                reply = string.Trim(reply)
                reply = string.gsub(reply, '^"', "")
                reply = string.gsub(reply, '"$', "")
                reply = string.Trim(reply)

                if reply == "" then return end

                if #reply > SmartManiac.Config.MaxPhraseLength then
                    reply = string.sub(reply, 1, SmartManiac.Config.MaxPhraseLength)
                end

                print("[Smart Maniac] AI reply to " .. ply:Nick() .. ": " .. reply)

                AddToHistory(npc, "assistant", reply)

                if IsValid(npc) then
                    SmartManiac.Sound.BroadcastPhrase(npc, reply)
                end
            end
        end,
        failed = function(err)
            print("[Smart Maniac] Conversation request failed: " .. tostring(err))
        end,
    })
end

--- Hook into player chat to detect messages near a maniac.
hook.Add("PlayerSay", "SmartManiac_Conversation", function(ply, text, teamChat)
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    local maniac = FindNearestManiac(ply)
    if not maniac then return end

    SmartManiac.Conversation.HandleChat(maniac, ply, text)
end)

print("[Smart Maniac] Conversation system loaded.")
