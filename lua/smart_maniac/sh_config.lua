--[[
    Smart Maniac NPC - Shared Configuration
    Configuration ConVars and constants shared between server and client.
]]

SmartManiac = SmartManiac or {}
SmartManiac.Config = SmartManiac.Config or {}

-- ============================================================
-- Detection ranges
-- ============================================================
SmartManiac.Config.SightRange        = 1500   -- Max distance the maniac can see a player
SmartManiac.Config.SightAngle        = 120    -- Field of view in degrees
SmartManiac.Config.HearingRange      = 800    -- Range to hear footsteps / gunshots
SmartManiac.Config.VoiceHearingRange = 1200   -- Range to hear player voice chat
SmartManiac.Config.CloseRange        = 120    -- Melee attack range

-- ============================================================
-- Movement speeds
-- ============================================================
SmartManiac.Config.WalkSpeed  = 80
SmartManiac.Config.RunSpeed   = 220
SmartManiac.Config.SprintSpeed = 300  -- When very close and chasing

-- ============================================================
-- Combat
-- ============================================================
SmartManiac.Config.AttackDamage   = 35
SmartManiac.Config.AttackCooldown = 1.2   -- Seconds between attacks
SmartManiac.Config.Health         = 500

-- ============================================================
-- AI Timings
-- ============================================================
SmartManiac.Config.PatrolWaitMin     = 2     -- Min seconds to wait at a patrol point
SmartManiac.Config.PatrolWaitMax     = 6     -- Max seconds to wait at a patrol point
SmartManiac.Config.InvestigateTime   = 10    -- Seconds to investigate a sound
SmartManiac.Config.LostTargetTime   = 15    -- Seconds before giving up on a lost target
SmartManiac.Config.ThinkInterval    = 0.15  -- AI think rate in seconds

-- ============================================================
-- OpenAI Integration
-- ============================================================
SmartManiac.Config.OpenAIEnabled   = false  -- Set to true to enable OpenAI
SmartManiac.Config.OpenAIModel     = "gpt-4o-mini"

SmartManiac.Config.ProviderURLs = {
    openai     = "https://api.openai.com/v1/chat/completions",
    openrouter = "https://openrouter.ai/api/v1/chat/completions",
}

function SmartManiac.Config.GetAPIUrl()
    local provider = "openai"
    if SERVER then
        provider = GetConVar("sm_maniac_openai_provider"):GetString()
    end
    return SmartManiac.Config.ProviderURLs[provider] or SmartManiac.Config.ProviderURLs["openai"]
end
SmartManiac.Config.PhraseInterval  = 5      -- Min seconds between AI-generated phrases
SmartManiac.Config.MaxPhraseLength = 200    -- Max characters for generated phrases

-- ============================================================
-- Voice / Sound
-- ============================================================
SmartManiac.Config.VoiceEnabled     = true
SmartManiac.Config.VoiceVolume      = 1.0
SmartManiac.Config.VoiceRange       = 1500   -- How far maniac voice can be heard

-- ============================================================
-- Voice AI (Speech Recognition & Conversation)
-- ============================================================
SmartManiac.Config.VoiceAIEnabled       = true   -- Enable voice AI (STT + AI response + TTS)
SmartManiac.Config.VoiceAIRange         = 1500   -- Range for voice AI conversation
SmartManiac.Config.VoiceAICooldown      = 2      -- Min seconds between voice AI responses
SmartManiac.Config.VoiceTTSRate         = 0.72   -- TTS playback rate (lower = deeper voice)
SmartManiac.Config.VoiceTTSVolume       = 1.0    -- TTS volume

-- ============================================================
-- Server ConVars (created server-side only)
-- ============================================================
if SERVER then
    CreateConVar("sm_maniac_enabled",        "1", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Enable Smart Maniac NPC")
    CreateConVar("sm_maniac_sight_range",    tostring(SmartManiac.Config.SightRange),    FCVAR_ARCHIVE, "Maniac sight range")
    CreateConVar("sm_maniac_hearing_range",  tostring(SmartManiac.Config.HearingRange),  FCVAR_ARCHIVE, "Maniac hearing range")
    CreateConVar("sm_maniac_voice_range",    tostring(SmartManiac.Config.VoiceHearingRange), FCVAR_ARCHIVE, "Range to hear player voice chat")
    CreateConVar("sm_maniac_walk_speed",     tostring(SmartManiac.Config.WalkSpeed),     FCVAR_ARCHIVE, "Maniac walk speed")
    CreateConVar("sm_maniac_run_speed",      tostring(SmartManiac.Config.RunSpeed),      FCVAR_ARCHIVE, "Maniac run speed")
    CreateConVar("sm_maniac_health",         tostring(SmartManiac.Config.Health),         FCVAR_ARCHIVE, "Maniac health")
    CreateConVar("sm_maniac_damage",         tostring(SmartManiac.Config.AttackDamage),   FCVAR_ARCHIVE, "Maniac attack damage")
    CreateConVar("sm_maniac_openai_enabled", "0", FCVAR_ARCHIVE, "Enable OpenAI integration (requires API key)")
    CreateConVar("sm_maniac_openai_key",     "",  FCVAR_PROTECTED, "OpenAI API key")
    CreateConVar("sm_maniac_openai_model",   SmartManiac.Config.OpenAIModel, FCVAR_ARCHIVE, "OpenAI model to use")
    CreateConVar("sm_maniac_openai_provider", "openai", FCVAR_ARCHIVE, "API provider: openai or openrouter")
    CreateConVar("sm_maniac_voice_ai",       "1", FCVAR_ARCHIVE, "Enable voice AI conversation (STT + response)")
    CreateConVar("sm_maniac_voice_tts_rate", "0.72", FCVAR_ARCHIVE, "TTS playback rate (lower = deeper voice, 0.5-1.0)")
end

--- Refresh config values from ConVars (server-side).
function SmartManiac.Config.Refresh()
    if not SERVER then return end
    SmartManiac.Config.SightRange        = GetConVar("sm_maniac_sight_range"):GetInt()
    SmartManiac.Config.HearingRange      = GetConVar("sm_maniac_hearing_range"):GetInt()
    SmartManiac.Config.VoiceHearingRange = GetConVar("sm_maniac_voice_range"):GetInt()
    SmartManiac.Config.WalkSpeed         = GetConVar("sm_maniac_walk_speed"):GetInt()
    SmartManiac.Config.RunSpeed          = GetConVar("sm_maniac_run_speed"):GetInt()
    SmartManiac.Config.Health            = GetConVar("sm_maniac_health"):GetInt()
    SmartManiac.Config.AttackDamage      = GetConVar("sm_maniac_damage"):GetInt()
    SmartManiac.Config.OpenAIEnabled     = GetConVar("sm_maniac_openai_enabled"):GetBool()
    SmartManiac.Config.VoiceAIEnabled    = GetConVar("sm_maniac_voice_ai"):GetBool()
end
