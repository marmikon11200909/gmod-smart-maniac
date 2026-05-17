--[[
    Smart Maniac NPC - OpenAI Integration
    Generates dynamic phrases and tactical decisions using the OpenAI API.
    Requires sm_maniac_openai_enabled 1 and a valid sm_maniac_openai_key.
]]

SmartManiac = SmartManiac or {}
SmartManiac.OpenAI = SmartManiac.OpenAI or {}

local SYSTEM_PROMPT = [[Ты — жуткий маньяк-NPC в хоррор-игре. Говори короткими жуткими фразами НА РУССКОМ ЯЗЫКЕ.
Правила:
- Максимум 10 слов в ответе
- Будь угрожающим, пугающим и зловещим
- Разнообразь фразы, никогда не повторяй одну и ту же дважды подряд
- Можешь ссылаться на то, что делаешь (патрулируешь, гонишься, ищешь, атакуешь)
- Иногда используй чёрный юмор
- ВСЕГДА говори ТОЛЬКО на русском языке
- Не используй кавычки в ответе]]

--- Generate a phrase via OpenAI.
-- @param context string  Description of what the maniac is doing.
-- @param callback function(phrase)  Called with the generated phrase.
function SmartManiac.OpenAI.GeneratePhrase(context, callback)
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    local body = util.TableToJSON({
        model = model,
        messages = {
            { role = "system",  content = SYSTEM_PROMPT },
            { role = "user",    content = "Текущее действие: " .. context .. ". Скажи короткую жуткую фразу на русском." },
        },
        max_tokens = 60,
        temperature = 0.9,
    })

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. apiKey,
    }

    SmartManiac.API.Request(apiUrl, "POST", headers, body,
        function(code, responseBody)
            if code ~= 200 then
                print("[Smart Maniac] OpenAI HTTP error code: " .. tostring(code))
                print("[Smart Maniac] Response: " .. tostring(responseBody))
                return
            end
            local data = util.JSONToTable(responseBody)
            if data and data.choices and data.choices[1] then
                local phrase = data.choices[1].message and data.choices[1].message.content or ""
                phrase = string.Trim(phrase)
                if #phrase > SmartManiac.Config.MaxPhraseLength then
                    phrase = string.sub(phrase, 1, SmartManiac.Config.MaxPhraseLength)
                end
                print("[Smart Maniac] AI phrase: " .. phrase)
                if callback then callback(phrase) end
            end
        end,
        function(err)
            print("[Smart Maniac] OpenAI request failed: " .. tostring(err))
        end
    )
end

--- Ask the AI for a tactical decision.
-- @param situation string  Description of the current situation.
-- @param options table     List of option strings.
-- @param callback function(chosenOption)
function SmartManiac.OpenAI.DecideTactic(situation, options, callback)
    if not GetConVar("sm_maniac_openai_enabled"):GetBool() then return end

    local apiKey = GetConVar("sm_maniac_openai_key"):GetString()
    if apiKey == "" then return end

    local model = GetConVar("sm_maniac_openai_model"):GetString()
    local apiUrl = SmartManiac.Config.GetAPIUrl()

    local optionsText = table.concat(options, ", ")
    local prompt = string.format(
        "Situation: %s\nOptions: %s\nChoose the best option. Reply with ONLY the option name.",
        situation, optionsText
    )

    local body = util.TableToJSON({
        model = model,
        messages = {
            { role = "system",  content = "You are a tactical AI for a horror game NPC. Choose the best hunting strategy. Reply with only the option name." },
            { role = "user",    content = prompt },
        },
        max_tokens = 20,
        temperature = 0.3,
    })

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. apiKey,
    }

    SmartManiac.API.Request(apiUrl, "POST", headers, body,
        function(code, responseBody)
            if code ~= 200 then
                print("[Smart Maniac] OpenAI tactic HTTP error: " .. tostring(code))
                return
            end
            local data = util.JSONToTable(responseBody)
            if data and data.choices and data.choices[1] then
                local choice = data.choices[1].message and data.choices[1].message.content or options[1]
                choice = string.Trim(choice)
                if callback then callback(choice) end
            end
        end,
        function(err)
            print("[Smart Maniac] OpenAI tactic request failed: " .. tostring(err))
            if callback then callback(options[1]) end
        end
    )
end
