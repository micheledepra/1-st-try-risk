# Game Flow Integration Summary

## Overview
Connected the MainMenu and PlayerSetup scenes from `_0_Game basics` to the main game flow, creating a complete player setup process before loading the map.

## Changes Made

### 1. Project Configuration (project.godot)
- **Changed**: Set MainMenu as the starting scene
- **From**: `run/main_scene="uid://b8p365k1ic0au"` (direct to Map)
- **To**: `run/main_scene="res://_0_Game basics/Scenes/MainMenu.tscn"`

### 2. GameManager.gd
Added support for the menu-driven player setup flow:
- **Added variable**: `var num_players: int = 0` - Stores the number of players selected
- **Added method**: `set_num_players(count: int)` - Sets player count from menu
- **Added method**: `start_player_setup()` - Initializes game state for player setup

### 3. MainMenu.gd
- **Fixed path**: Changed scene path from `res://scenes/PlayerSetup.tscn` to `res://_0_Game basics/Scenes/PlayerSetup.tscn`
- Now properly calls `GameManager.set_num_players()` and `GameManager.start_player_setup()` before transitioning

### 4. PlayerSetup.gd
Updated to work with existing GameManager and Player class:
- **Changed**: Player creation now uses `Player.new()` class directly instead of non-existent `PlayerManager`
- **Changed**: Players are added to `GameManager.players` array
- **Fixed**: `start_game()` now calls existing GameManager methods:
  - `distribute_territories_randomly()` - Distributes territories among players
  - `assign_initial_armies()` - Gives players initial armies
  - Emits proper signals for turn and phase changes
- **Fixed path**: Changed from `res://scenes/GameMap.tscn` to `res://Scenes/Map.tscn`

### 5. Map.gd
Added logic to detect if game was initialized from menu:
- **Added method**: `update_territory_visuals()` - Updates visual state for pre-initialized territories
- **Modified**: `_ready()` now checks if players already exist before calling `start_game()`
- This prevents overwriting the player setup done through the menu system

## Game Flow

The game now follows this sequence:

1. **MainMenu.tscn** - Player selects number of players (2-6)
2. **PlayerSetup.tscn** - Each player enters name and chooses color
3. **Map.tscn** - Game loads with territories distributed and initial armies assigned

## How It Works

### Startup Sequence:
1. Game launches → MainMenu scene loads
2. Player selects number of players → GameManager stores this value
3. Player clicks "Start Game" → Transitions to PlayerSetup
4. For each player:
   - Enter name (or use default "Player X")
   - Choose color from available options
   - Click "Next Player" (or "Start Game" for last player)
5. After last player setup:
   - GameManager distributes all territories randomly
   - GameManager assigns initial armies based on player count
   - Scene changes to Map.tscn
6. Map scene loads:
   - Detects players are already set up
   - Updates territory visuals to match game state
   - Game begins in SETUP phase

### Initial Army Distribution:
Based on classic Risk rules (from GameManager):
- 2 players: 40 armies each
- 3 players: 35 armies each
- 4 players: 30 armies each
- 5 players: 25 armies each
- 6 players: 20 armies each

Each player gets 1 army automatically placed on each territory they own, with remaining armies available in their reserve.

## Testing
To test the integration:
1. Run the project
2. Select number of players on main menu
3. Enter names and colors for each player
4. Verify map loads with territories distributed
5. Check that GameUI shows correct player information
