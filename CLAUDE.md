# Project: 1st Try Risk

## Godot Version
This project uses **Godot 4.5**. When consulting documentation via context7, always request docs for Godot 4.5 (not 4.3, 4.4, or older). The Godot executable is at `C:/GODOT/Godot_v4.5.1-stable_win64.exe`.

## Project Overview
3D Risk board game clone. 42 territories, 6 continents, 2–6 players, classic Risk rules.

## Architecture
- **GameManager.gd** (autoload singleton) — all game state, phases, turn management
- **AttackPhase.gd** — dice combat, territory conquest
- **ReinforcementPhase.gd** — army placement
- **FortifyPhase.gd** — army movement (BFS connectivity)
- **Scripts/Map/** — Map.gd + 6 territory sub-managers (color, input, unit, transparency, tooltip, camera)
- **UI/** — gameUI_01.gd, AttackResolutionUI, TransferUnitsUI, DataDashboard
- **map_data.json** — 42 territories with neighbors & continents

## Game Phase Enum
`SETUP → REINFORCEMENT → ATTACK → FORTIFY → GAME_OVER`

## Main Scene
`_0_Game basics/Scenes/MainMenu.tscn`

## Key Conventions
- Material pooling per-continent per-player (not per-unit)
- 2D UI overlay instead of Label3D billboards for performance
- Physics-free units (no RigidBody, no collision for decorative units)
- Event-driven tweens, not per-frame updates

## MCP Tools Available
- **context7** — Godot 4.5 documentation lookup. Use `resolve-library-id` then `get-library-docs` for GDScript/Godot API questions.
- **godot** — Live Godot editor control. Can manipulate scenes, nodes, run scripts, read project state.
