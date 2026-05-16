--[[
    Smart Maniac NPC - Subtitle System (Client)
    Displays conversation subtitles at the bottom of the screen.
    Shows player speech, maniac responses, and listening indicators.
]]

SmartManiac = SmartManiac or {}
SmartManiac.Subtitles = SmartManiac.Subtitles or {}

local subtitleQueue = {}
local liveText = ""
local isListening = false
local SUBTITLE_MAX = 5
local SUBTITLE_FONT = "SmartManiac_SubtitleFont"
local SUBTITLE_FONT_SMALL = "SmartManiac_SubtitleSmall"

-- Create fonts
surface.CreateFont(SUBTITLE_FONT, {
    font = "Roboto",
    size = 22,
    weight = 600,
    antialias = true,
    shadow = true,
})

surface.CreateFont(SUBTITLE_FONT_SMALL, {
    font = "Roboto",
    size = 16,
    weight = 500,
    antialias = true,
    shadow = true,
})

--- Add a subtitle to the display queue.
-- @param speaker string  Name of who is speaking
-- @param text string  The subtitle text
-- @param color Color  Color for the speaker name
-- @param duration number  How long to display (seconds)
function SmartManiac.Subtitles.Add(speaker, text, color, duration)
    duration = duration or 4
    color = color or Color(255, 255, 255)

    table.insert(subtitleQueue, {
        speaker = speaker,
        text = text,
        color = color,
        startTime = CurTime(),
        duration = duration,
        alpha = 0,
        fadeIn = true,
    })

    while #subtitleQueue > SUBTITLE_MAX do
        table.remove(subtitleQueue, 1)
    end
end

--- Set live (interim) subtitle text while player is speaking.
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

    local padding = 8
    local boxW = tw + padding * 2
    local boxH = th + padding

    draw.RoundedBox(4, x - boxW / 2, y - padding / 2, boxW, boxH, Color(0, 0, 0, bgAlpha * 0.7))
    draw.SimpleText(text, font, x, y, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    return boxH + 4
end

-- HUD rendering
hook.Add("HUDPaint", "SmartManiac_Subtitles", function()
    local scrW, scrH = ScrW(), ScrH()
    local baseY = scrH - 60
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
        DrawSubtitleBox(
            "[MIC] Слушаю" .. dots,
            centerX, baseY,
            Color(100, 255, 100, listenAlpha),
            120,
            SUBTITLE_FONT_SMALL
        )
        baseY = baseY - 28
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
            100,
            SUBTITLE_FONT_SMALL
        )
        baseY = baseY - 28
    end

    -- Draw queued subtitles (newest at bottom)
    for i = #subtitleQueue, 1, -1 do
        local sub = subtitleQueue[i]
        local elapsed = CurTime() - sub.startTime
        local remaining = sub.duration - elapsed

        -- Fade in/out
        local alpha = 255
        if elapsed < 0.3 then
            alpha = math.floor((elapsed / 0.3) * 255)
        elseif remaining < 0.5 then
            alpha = math.floor((remaining / 0.5) * 255)
        end
        alpha = math.Clamp(alpha, 0, 255)

        if alpha <= 0 then continue end

        -- Build display text
        local displayText = sub.text
        if #displayText > 120 then
            displayText = string.sub(displayText, 1, 117) .. "..."
        end

        local speakerColor = Color(sub.color.r, sub.color.g, sub.color.b, alpha)
        local textColor = Color(255, 255, 255, alpha)

        -- Draw speaker name + text
        surface.SetFont(SUBTITLE_FONT)
        local speakerW = surface.GetTextSize(sub.speaker .. ": ")
        local textW = surface.GetTextSize(displayText)
        local totalW = speakerW + textW
        local padding = 10
        local boxW = totalW + padding * 2

        surface.SetFont(SUBTITLE_FONT)
        local _, textH = surface.GetTextSize(displayText)
        local boxH = textH + padding

        local boxX = centerX - boxW / 2
        local boxY = baseY - padding / 2

        draw.RoundedBox(4, boxX, boxY, boxW, boxH, Color(0, 0, 0, alpha * 0.7))

        local textStartX = centerX - totalW / 2
        draw.SimpleText(sub.speaker .. ": ", SUBTITLE_FONT, textStartX, baseY, speakerColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(displayText, SUBTITLE_FONT, textStartX + speakerW, baseY, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        baseY = baseY - (boxH + 4)
    end
end)

-- Receive maniac phrase for subtitle display
net.Receive("SmartManiac_Phrase", function()
    local npc = net.ReadEntity()
    local phrase = net.ReadString()

    if phrase and phrase ~= "" then
        SmartManiac.Subtitles.Add("Маньяк", phrase, Color(255, 60, 60), 5)
    end

    -- Also trigger TTS
    if SmartManiac.TTS and SmartManiac.TTS.Speak and IsValid(npc) then
        SmartManiac.TTS.Speak(npc, phrase)
    end
end)

print("[Smart Maniac] Subtitle system loaded.")
