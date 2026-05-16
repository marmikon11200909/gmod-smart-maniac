# Smart Maniac NPC — Garry's Mod Addon

AI-powered maniac NPC for Garry's Mod with voice detection, intelligent hunting behavior, and optional OpenAI integration.

## Features

- **Intelligent AI** — finite state machine with states: Idle, Patrol, Investigate, Chase, Attack, Lost Target
- **Voice Detection** — reacts to players using voice chat nearby and investigates the sound source
- **Player Detection** — sees players (FOV + line-of-sight), hears running/shooting/jumping
- **OpenAI Integration** (optional) — generates dynamic creepy phrases and tactical decisions via GPT
- **Visual Effects** — glowing red eyes, floating phrase bubbles, screen effects when being chased, directional threat indicator, atmospheric overlays
- **Customizable** — all parameters adjustable via ConVars and in-game settings panel
- **Spawn Menu** — available in the NPC spawn menu under "Smart Maniac" category

## Installation

1. Download or clone this repository
2. Place the `gmod-smart-maniac` folder into your Garry's Mod addons directory:
   ```
   Steam/steamapps/common/GarrysMod/garrysmod/addons/
   ```
3. Restart Garry's Mod or run `lua_reloadents` in console

## Usage

### Spawning
- **Spawn Menu**: Find "Smart Maniac" in the NPC tab
- **Console**: `sm_maniac_spawn`

### Console Commands
| Command | Description |
|---------|-------------|
| `sm_maniac_spawn` | Spawn a maniac at your crosshair |
| `sm_maniac_remove_all` | Remove all maniacs from the map |
| `sm_maniac_reload_config` | Reload config from ConVars |

### Settings
Open the **Utilities** tab in the spawn menu → **Smart Maniac** → **Settings**

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
| `sm_maniac_openai_enabled` | 0 | Enable OpenAI integration |
| `sm_maniac_openai_key` | "" | Your OpenAI API key |
| `sm_maniac_openai_model` | gpt-4o-mini | OpenAI model to use |
| `sm_maniac_debug_hud` | 0 | Show debug HUD (client) |

## OpenAI Integration

To enable AI-generated phrases:

1. Set `sm_maniac_openai_enabled 1` in console
2. Set `sm_maniac_openai_key YOUR_API_KEY` in console
3. The maniac will generate dynamic creepy phrases based on its current state

Without OpenAI, the maniac uses a built-in set of predefined phrases (in Russian by default).

## AI Behavior

```
IDLE → PATROL → (sees player) → CHASE → (close enough) → ATTACK
                ↓                  ↓
         (hears voice/noise)   (loses sight)
                ↓                  ↓
          INVESTIGATE         LOST TARGET → (timeout) → PATROL
```

- **Patrol**: Wanders between random navmesh points, occasionally mumbles
- **Investigate**: Heard a noise or voice chat — moves to the source
- **Chase**: Spotted a player — runs toward them
- **Attack**: Close enough — melee attack with damage
- **Lost Target**: Lost line of sight — searches last known position
- **Damaged**: If shot, immediately targets the attacker

## Requirements

- Garry's Mod (licensed)
- Maps with navmesh for best pathfinding (`nav_generate` in console)
- OpenAI API key (optional, for AI-generated phrases)

## License

MIT
