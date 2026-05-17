--[[
    Smart Maniac NPC - Subtitle System (Client) - IMPROVED
    Displays conversation subtitles at the bottom of the screen.
    Shows player speech, maniac responses, listening indicators.
    Handles SmartManiac_Phrase net message and triggers TTS.
]]

SmartManiac = SmartManiac or {}
SmartManiac.Subtitles = SmartManiac.Subtitles or {}

local subtitleQueue = {}
local liveText = ""
local isListening = false
local SUBTITLE_MAX = 6
local SUBTITLE_FONT = "SmartManiac_SubtitleFont"
local SUBTITLE_FONT_SMALL = "SmartManiac_SubtitleSmall"

surface.CreateFont(SUBTITLE_FONT, {
    font = "Arial",
    size = 24,
    weight = 700,
    antialias = true,
    shadow = true,
})

surface.CreateFont(SUBTITLE_FONT_SMALL, {
    font = "Arial",
    size = 18,
    weight = 500,
    antialias = true,
    shadow = true,
})

--- Add a subtitle to the display queue.
function SmartManiac.Subtitles.Add(speaker, text, color, duration)
    duration = duration or 5
    color = color or Color(255, 255, 255)

    table.insert(subtitleQueue, {
        speaker = speaker,
        text = text,
        color = color,
        startTime = CurTime(),
        duration = duration,
        alpha = 0,
    })

    while #subtitleQueue > SUBTITLE_MAX do
        table.remove(subtitleQueue, 1)
    end
end

--- Set live (interim) subtitle text.
function SmartManiac.Subtitles.SetLive(text)
    liveText = text or ""
end

--- Clear live subtitle.
function SmartManiac.Subtitles.ClearLive()
    liveText = ""
end

--- Show/hide listening indicator.
function SmartManiac.Subtitles.ShowListening(show)
    isListening = show or false
end

--- Draw a text with background box.
local function DrawSubtitleBox(text, x, y, textColor, bgAlpha, font)
    font = font or SUBTITLE_FONT
    surface.SetFont(font)
    local tw, th = surface.GetTextSize(text)

    local padding = 10
    local boxW = tw + padding * 2
    local boxH = th + padding

    draw.RoundedBox(6, x - boxW / 2, y - padding / 2, boxW, boxH, Color(0, 0, 0, bgAlpha * 0.75))
    draw.SimpleText(text, font, x, y, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    return boxH + 4
end

-- HUD rendering
hook.Add("HUDPaint", "SmartManiac_Subtitles", function()
    local scrW, scrH = ScrW(), ScrH()
    local baseY = scrH - 70
    local centerX = scrW / 2

    -- Clean up expired subtitles
    for i = #subtitleQueue, 1, -1 do
        local sub = subtitleQueue[i]
        if CurTime() - sub.startTime > sub.duration + 0.5 then
            table.remove(subtitleQueue, i)
        end
    end

    -- Draw listening indicator
    if isListening then
        local dots = string.rep(".", math.floor(CurTime() * 2) % 4)
        local listenAlpha = 150 + math.sin(CurTime() * 3) * 50
        local micIcon = "[MIC]"
        DrawSubtitleBox(
            micIcon .. " \xd0\xa1\xd0\xbb\xd1\x83\xd1\x88\xd0\xb0\xd1\x8e" .. dots,
            centerX, baseY,
            Color(100, 255, 100, listenAlpha),
            140,
            SUBTITLE_FONT_SMALL
        )
        baseY = baseY - 30
    end

    -- Draw live (interim) text
    if liveText ~= "" then
        local liveAlpha = 180 + math.sin(CurTime() * 4) * 40
        local displayText = liveText
        if #displayText > 80 then
            displayText = "..." .. string.sub(displayText, #displayText - 77)
        end

        DrawSubtitleBox(
            displayText,
            centerX, baseY,
            Color(180, 200, 255, liveAlpha),
            110,
            SUBTITLE_FONT_SMALL
        )
        baseY = baseY - 30
    end

    -- Draw queued subtitles (newest at bottom)
    for i = #subtitleQueue, 1, -1 do
        local sub = subtitleQueue[i]
        local elapsed = CurTime() - sub.startTime
        local remaining = sub.duration - elapsed

        local alpha = 255
        if elapsed < 0.3 then
            alpha = math.floor((elapsed / 0.3) * 255)
        elseif remaining < 0.5 then
            alpha = math.floor((remaining / 0.5) * 255)
        end
        alpha = math.Clamp(alpha, 0, 255)

        if alpha <= 0 then continue end

        local displayText = sub.text
        if #displayText > 120 then
            displayText = string.sub(displayText, 1, 117) .. "..."
        end

        local speakerColor = Color(sub.color.r, sub.color.g, sub.color.b, alpha)
        local textColor = Color(255, 255, 255, alpha)

        surface.SetFont(SUBTITLE_FONT)
        local speakerW = surface.GetTextSize(sub.speaker .. ": ")
        local textW = surface.GetTextSize(displayText)
        local totalW = speakerW + textW
        local padding = 12
        local boxW = totalW + padding * 2

        local _, textH = surface.GetTextSize(displayText)
        local boxH = textH + padding

        local boxX = centerX - boxW / 2
        local boxY = baseY - padding / 2

        draw.RoundedBox(6, boxX, boxY, boxW, boxH, Color(0, 0, 0, alpha * 0.75))

        local textStartX = centerX - totalW / 2
        draw.SimpleText(sub.speaker .. ": ", SUBTITLE_FONT, textStartX, baseY, speakerColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(displayText, SUBTITLE_FONT, textStartX + speakerW, baseY, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        baseY = baseY - (boxH + 4)
    end
end)

-- Receive maniac phrase for subtitle display AND trigger TTS
net.Receive("SmartManiac_Phrase", function()
    local npc = net.ReadEntity()
    local phrase = net.ReadString()
    local speechType = net.ReadString()

    if not phrase or phrase == "" then return end
    if not speechType or speechType == "" then speechType = "proactive" end

    -- Different subtitle label and color based on speech type
    local speakerLabel = "Маньяк"
    local speakerColor = Color(255, 60, 60)

    if speechType == "response" then
        speakerLabel = "Маньяк [ответ]"
        speakerColor = Color(255, 120, 40)
    elseif speechType == "imitation" then
        speakerLabel = "Маньяк [передразнивает]"
        speakerColor = Color(255, 180, 0)
    end

    -- Show subtitle
    SmartManiac.Subtitles.Add(speakerLabel, phrase, speakerColor, 6)

    -- Trigger TTS voice playback
    if SmartManiac.TTS and SmartManiac.TTS.Speak and IsValid(npc) then
        SmartManiac.TTS.Speak(npc, phrase)
    end

    -- Notify other systems (e.g. 3D phrase bubble in cl_init.lua)
    hook.Run("SmartManiac_PhraseReceived", npc, phrase, speechType)

    print("[Smart Maniac] Received phrase (" .. speechType .. "): " .. string.sub(phrase, 1, 80))
end)

print("[Smart Maniac] Subtitle system loaded.")
