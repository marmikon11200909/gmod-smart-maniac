# Smart Maniac NPC — Garry's Mod Addon

AI-powered maniac NPC for Garry's Mod with **live voice AI conversation**, intelligent hunting behavior, and OpenRouter/OpenAI integration. Talk to the maniac through your microphone — he'll understand you and respond with a deep, menacing voice!

## Features

- **Live Voice AI** — speak through Garry's Mod voice chat and the maniac responds with AI-generated phrases in a deep male voice
- **Speech Recognition** — captures your voice via Web Speech API (DHTML) and transcribes what you say
- **AI Conversation** — generates contextual responses based on what you said, the maniac's state, and game situation
- **Deep Male Voice TTS** — maniac speaks back with a rough, menacing voice (Google TTS primary + SpeechSynthesis bonus)
- **Proactive Speaking** — maniac talks on his own when near players (random AI phrases, taunts, mumbling)
- **Voice Imitation** — maniac can mock and repeat your words sarcastically (30% chance per response)
- **Subtitles** — on-screen subtitles showing your speech (blue) and maniac's responses (red) with animations
- **Echo Effect** — 3D positional audio with echo for menacing atmosphere
- **Intelligent AI** — finite state machine with states: Idle, Patrol, Investigate, Chase, Attack, Lost Target
- **Voice Detection** — reacts to players using voice chat nearby and investigates the sound source
- **Player Detection** — sees players (FOV + line-of-sight), hears running/shooting/jumping
- **OpenRouter Support** — works with OpenRouter API (for regions where OpenAI is blocked)
- **Visual Effects** — glowing red eyes, floating phrase bubbles, screen effects when being chased, directional threat indicator, atmospheric overlays
- **Text Chat** — also responds to text chat messages near the maniac
- **Quick Setup** — one command to configure everything: `sm_maniac_setup YOUR_KEY`
- **Customizable** — all parameters adjustable via ConVars and in-game settings panel
- **Spawn Menu** — available in the NPC spawn menu under "Smart Maniac" category

## Installation

### Method 1: Automatic (Python installer)
1. Download ZIP: [Download](https://github.com/marmikon11200909/gmod-smart-maniac/archive/refs/heads/base.zip)
2. Unzip the archive
3. Open the `gmod-smart-maniac-init` folder
4. Double-click `install.bat` (or right-click `install.py` → Open with Python)
5. The installer will find GMod automatically and copy files

**Requirements:** Python 3 must be installed. Download from [python.org](https://www.python.org/downloads/) — check "Add to PATH" during install!

### Method 2: Manual (100% works, no Python needed)
1. Download ZIP: [Download](https://github.com/marmikon11200909/gmod-smart-maniac/archive/refs/heads/base.zip)
2. Unzip the archive
3. Find your GMod addons folder:
   - Open **Steam** → Right-click **Garry's Mod** → **Properties** → **Local Files** → **Browse**
   - Open folder `garrysmod` → `addons`
4. Copy the `gmod-smart-maniac-init` folder into `addons`
5. **Rename** the copied folder from `gmod-smart-maniac-init` to `gmod-smart-maniac`
6. Final path should look like: `GarrysMod/garrysmod/addons/gmod-smart-maniac/lua/...`
7. Restart Garry's Mod

## Quick Start — Voice AI

### One-Command Setup (Recommended)
```
sm_maniac_setup YOUR_OPENROUTER_API_KEY
sm_maniac_spawn
```
Done! Walk up to the maniac and press V to talk.

### Manual Setup
1. Open console and set up the API:
   ```
   sm_maniac_openai_enabled 1
   sm_maniac_openai_provider openrouter
   sm_maniac_openai_key YOUR_OPENROUTER_API_KEY
   sm_maniac_openai_model gpt-4o-mini
   sm_maniac_voice_ai 1
   ```
2. Spawn a maniac: `sm_maniac_spawn`
3. Walk up to the maniac and **press V** (voice chat key)
4. **Talk!** The maniac will hear you, understand what you said, and respond with a deep menacing voice
5. **Wait!** The maniac will also talk on his own when you're nearby!
6. Check voice AI status: `sm_maniac_voice_status`

### How Voice AI Works

```
You speak (V key) -> Microphone captured -> Speech-to-Text ->
  -> AI generates response -> Maniac speaks back (deep voice TTS)
```

1. When you press the voice chat key, the addon captures your microphone via a DHTML panel
2. Your speech is transcribed using Web Speech API (built into Chrome/CEF)
3. The transcribed text is sent to the server
4. The server sends your message + game context to OpenRouter/OpenAI
5. The AI generates a response as the maniac character
6. The response is displayed as text above the maniac and spoken via TTS with a deep male voice

**Fallback:** If speech recognition is unavailable in your GMod build, the maniac will still react to your voice with contextual AI-generated responses based on the game situation.

## Usage

### Spawning
- **Spawn Menu**: Find "Smart Maniac" in the NPC tab
- **Console**: `sm_maniac_spawn`

### Console Commands
| Command | Description |
|---------|-------------|
| `sm_maniac_setup KEY` | **Quick setup** — enables AI, OpenRouter, voice AI in one command |
| `sm_maniac_spawn` | Spawn a maniac at your crosshair |
| `sm_maniac_remove_all` | Remove all maniacs from the map |
| `sm_maniac_reload_config` | Reload config from ConVars |
| `sm_maniac_test_openai` | Test AI API connection |
| `sm_maniac_voice_status` | Check voice AI status (client) |
| `sm_maniac_voice_debug` | Full voice system diagnostics (server) |
| `sm_maniac_say TEXT` | Force maniac to say specific text |
| `sm_maniac_say` | Trigger random proactive phrase |

### Settings
Open the **Utilities** tab in the spawn menu -> **Smart Maniac** -> **Settings**

### ConVars
| ConVar | Default | Description |
|--------|---------|-------------|
| `sm_maniac_enabled` | 1 | Enable/disable the maniac NPC |
| `sm_maniac_sight_range` | 1500 | How far the maniac can see |
| `sm_maniac_hearing_range` | 800 | How far footsteps/gunshots are heard |
| `sm_maniac_voice_range` | 1200 | How far voice chat is detected |
| `sm_maniac_walk_speed` | 80 | Walking speed |
| `sm_maniac_run_speed` | 220 | Running speed |
| `sm_maniac_health` | 500 | Maniac health points |
| `sm_maniac_damage` | 35 | Attack damage per hit |
| `sm_maniac_openai_enabled` | 0 | Enable AI integration |
| `sm_maniac_openai_key` | "" | API key (OpenAI or OpenRouter) |
| `sm_maniac_openai_model` | gpt-4o-mini | AI model to use |
| `sm_maniac_openai_provider` | openai | API provider: `openai` or `openrouter` |
| `sm_maniac_voice_ai` | 1 | Enable voice AI conversation |
| `sm_maniac_voice_tts_rate` | 0.72 | Voice depth (lower = deeper, 0.5-1.0) |
| `sm_maniac_debug_hud` | 0 | Show debug HUD (client) |

## OpenRouter Setup (Recommended for blocked regions)

If OpenAI is blocked in your region, use OpenRouter:

1. Go to [openrouter.ai](https://openrouter.ai) and create an account
2. Get your API key from the dashboard
3. In GMod console:
   ```
   sm_maniac_openai_enabled 1
   sm_maniac_openai_provider openrouter
   sm_maniac_openai_key sk-or-v1-YOUR_KEY_HERE
   sm_maniac_openai_model gpt-4o-mini
   ```
4. Test connection: `sm_maniac_test_openai`

## AI Behavior

```
IDLE -> PATROL -> (sees player) -> CHASE -> (close enough) -> ATTACK
                |                    |
         (hears voice/noise)    (loses sight)
                |                    |
          INVESTIGATE          LOST TARGET -> (timeout) -> PATROL
```

- **Patrol**: Wanders between random navmesh points, occasionally mumbles
- **Investigate**: Heard a noise or voice chat — moves to the source, speaks
- **Chase**: Spotted a player — runs toward them, taunts
- **Attack**: Close enough — melee attack with damage
- **Lost Target**: Lost line of sight — searches last known position
- **Damaged**: If shot, immediately targets the attacker
- **Voice Conversation**: When you speak via voice chat, the maniac responds with AI-generated dialogue

## Voice AI Architecture

```
lua/smart_maniac/
  cl_voice_capture.lua      -- DHTML speech recognition (client)
  cl_voice_detection.lua    -- Voice chat detection hooks (client)
  cl_tts.lua                -- Text-to-Speech: Google TTS primary + SpeechSynthesis (client)
  cl_subtitles.lua          -- Subtitle display system (client)
  cl_hud.lua                -- HUD effects and indicators (client)
  sv_voice_conversation.lua -- Voice AI: conversation + proactive speech + imitation (server)
  sv_voice_detection.lua    -- Voice detection server logic (server)
  sv_conversation.lua       -- Text chat conversation (server)
  sv_openai.lua             -- OpenAI/OpenRouter API (server)
  sv_ai_brain.lua           -- AI state machine (server)
  sv_sound_system.lua       -- Sound/phrase system (server)
  sh_config.lua             -- Shared configuration (shared)
```

## Requirements

- Garry's Mod (licensed)
- Maps with navmesh for best pathfinding (`nav_generate` in console)
- OpenRouter or OpenAI API key (required for AI features)
- Microphone (for voice AI conversation)

## License

MIT
