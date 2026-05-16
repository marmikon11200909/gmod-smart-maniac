--[[
    Smart Maniac NPC - Sound / Voice System
    Handles the maniac's voice lines, ambient sounds, and text-to-speech display.
    Uses a combination of built-in HL2 sounds and network messages
    to display AI-generated phrases as 3D text above the NPC.
]]

SmartManiac = SmartManiac or {}
SmartManiac.Sound = SmartManiac.Sound or {}

-- ============================================================
-- Predefined voice lines (using HL2 zombie / combine sounds)
-- ============================================================
SmartManiac.Sound.Lines = {
    idle = {
        "npc/zombie/zombie_voice_idle1.wav",
        "npc/zombie/zombie_voice_idle2.wav",
        "npc/zombie/zombie_voice_idle3.wav",
        "npc/zombie/zombie_voice_idle4.wav",
        "npc/zombie/zombie_voice_idle5.wav",
        "npc/zombie/zombie_voice_idle6.wav",
    },
    chase = {
        "npc/zombie/zombie_alert1.wav",
        "npc/zombie/zombie_alert2.wav",
        "npc/zombie/zombie_alert3.wav",
    },
    attack = {
        "npc/zombie/zombie_attack1.wav",
        "npc/zombie/zombie_attack2.wav",
    },
    lost = {
        "npc/zombie/zombie_voice_idle1.wav",
        "npc/zombie/zombie_voice_idle3.wav",
        "npc/zombie/zombie_voice_idle5.wav",
    },
    investigate = {
        "npc/zombie/zombie_voice_idle2.wav",
        "npc/zombie/zombie_voice_idle4.wav",
    },
    pain = {
        "npc/zombie/zombie_pain1.wav",
        "npc/zombie/zombie_pain2.wav",
        "npc/zombie/zombie_pain3.wav",
        "npc/zombie/zombie_pain4.wav",
        "npc/zombie/zombie_pain5.wav",
        "npc/zombie/zombie_pain6.wav",
    },
    death = {
        "npc/zombie/zombie_die1.wav",
        "npc/zombie/zombie_die2.wav",
        "npc/zombie/zombie_die3.wav",
    },
    spot = {
        "npc/zombie/zombie_alert1.wav",
        "npc/zombie/zombie_alert2.wav",
        "npc/zombie/zombie_alert3.wav",
    },
}

-- Predefined text phrases (used when OpenAI is disabled)
SmartManiac.Sound.TextPhrases = {
    idle = {
        "...",
        "*тяжёлое дыхание*",
        "Где же вы...",
        "Я слышу тебя...",
        "Тишина... мне нравится...",
    },
    chase = {
        "Беги! Беги! Ха-ха-ха!",
        "Я вижу тебя!",
        "Тебе не убежать!",
        "Иди сюда!",
        "Ты моя добыча!",
        "Не убегай, будет больнее!",
    },
    attack = {
        "УМРИ!",
        "Получай!",
        "Ха-ха-ха!",
        "Больно, да?",
        "Это только начало!",
    },
    lost = {
        "Куда ты делся?...",
        "Я найду тебя...",
        "Ты не спрячешься...",
        "Выходи, не бойся...",
        "Рано или поздно я тебя найду...",
    },
    investigate = {
        "Что это было?",
        "Кто здесь?",
        "Я слышал тебя...",
        "Покажись!",
        "Интересно...",
    },
    spot = {
        "Вот ты где!",
        "Нашёл!",
        "Попался!",
        "Не спрятался!",
    },
}

--- Play a sound from a category on the NPC.
-- @param npc Entity
-- @param category string  One of the keys in SmartManiac.Sound.Lines
function SmartManiac.Sound.PlaySound(npc, category)
    if not IsValid(npc) then return end

    local sounds = SmartManiac.Sound.Lines[category]
    if not sounds or #sounds == 0 then return end

    local snd = sounds[math.random(#sounds)]
    npc:EmitSound(snd, SmartManiac.Config.VoiceRange, 100, SmartManiac.Config.VoiceVolume)
end

--- Show a text phrase above the NPC to all nearby players.
-- Uses AI-generated phrase if OpenAI is enabled, otherwise picks from preset.
-- @param npc Entity
-- @param category string
function SmartManiac.Sound.SayPhrase(npc, category)
    if not IsValid(npc) then return end

    -- Cooldown
    if CurTime() < (npc.sm_nextPhrase or 0) then return end
    npc.sm_nextPhrase = CurTime() + SmartManiac.Config.PhraseInterval

    -- Play a sound effect regardless
    SmartManiac.Sound.PlaySound(npc, category)

    -- Generate or pick a text phrase
    if GetConVar("sm_maniac_openai_enabled"):GetBool() then
        local contextMap = {
            idle        = "патрулирую пустую территорию, прислушиваюсь к звукам",
            chase       = "гонюсь за убегающей жертвой по коридорам",
            attack      = "атакую жертву вблизи",
            lost        = "потерял жертву из виду, ищу вокруг",
            investigate = "услышал странный звук и иду проверить",
            spot        = "только что заметил прячущуюся жертву",
        }
        local ctx = contextMap[category] or "брожу по территории в поисках жертв"

        SmartManiac.OpenAI.GeneratePhrase(ctx, function(phrase)
            if phrase and phrase ~= "" and IsValid(npc) then
                SmartManiac.Sound.BroadcastPhrase(npc, phrase)
            end
        end)
    else
        local phrases = SmartManiac.Sound.TextPhrases[category]
        if phrases and #phrases > 0 then
            local phrase = phrases[math.random(#phrases)]
            SmartManiac.Sound.BroadcastPhrase(npc, phrase)
        end
    end
end

--- Broadcast a phrase to clients so it can be rendered above the NPC.
-- @param npc Entity
-- @param phrase string
function SmartManiac.Sound.BroadcastPhrase(npc, phrase)
    if not IsValid(npc) then return end

    net.Start("SmartManiac_Phrase")
        net.WriteEntity(npc)
        net.WriteString(phrase)
    net.Broadcast()
end
