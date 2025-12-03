# GameUI_01 Integration Steps

## Completed Implementation

### 1. Created `UI/game_ui_01.gd`
- Full GameManager signal connections
- Real-time UI updates for all game data
- Panel positioning logic (top-left, top-right, top-center, bottom-right)
- Phase-specific instructions and button behavior
- Public method `set_instruction_text()` for Map.gd feedback

### 2. Updated `Scripts/Map/Map.gd`
- Added `game_ui: Control` reference
- Integrated UI lookup via `CanvasLayer/GameUI_01`
- Enhanced attack/fortify handlers with UI feedback
- Dynamic instruction updates during territory selection

### 3. Verified GameManager Integration
- All required signals exist: `turn_changed`, `phase_changed`, `game_over`, `armies_changed`
- All required methods exist: `get_current_player()`, `advance_phase()`, `end_turn()`
- Territory management methods: `get_territory_armies()`, `add_armies_to_territory()`, `get_territory_owner()`
- Player class uses `territories_owned` array correctly

## Manual Steps Required in Godot Editor

### Step 1: Attach Script to GameUI_01 Scene
1. Open `UI/GameUI_01.tscn` in Godot
2. Select the root Control node
3. In Inspector, click "Attach Script" 
4. Select the existing `UI/game_ui_01.gd` script
5. Save the scene

### Step 2: Set Unique Names for UI Elements
The script uses `%NodeName` syntax, so you need to set unique names:

1. In GameUI_01.tscn scene tree, find and set these unique names:
   - PlayerNameLabel → Right-click → "Access as Unique Name"
   - ArmyLabel → Right-click → "Access as Unique Name"
   - TerritoryLabel → Right-click → "Access as Unique Name"
   - ReinforcementsLabel → Right-click → "Access as Unique Name"
   - TurnNumberLabel → Right-click → "Access as Unique Name"
   - PhaseLabel → Right-click → "Access as Unique Name"
   - PlayerPositionLabel → Right-click → "Access as Unique Name"
   - InstructionLabel → Right-click → "Access as Unique Name"
   - ConfirmButton → Right-click → "Access as Unique Name"

2. Save the scene

### Step 3: Connect Confirm Button Signal
1. In GameUI_01.tscn, select ConfirmButton
2. In Node tab, find "pressed()" signal
3. Connect to the GameUI_01 root node
4. Select method: `_on_confirm_button_pressed`
5. Click Connect

### Step 4: Verify Scene Hierarchy in Map.tscn
1. Open `Scenes/Map.tscn`
2. Verify hierarchy:
   ```
   Map (Node3D)
   ├── CanvasLayer
   │   └── GameUI_01 (instance of GameUI_01.tscn)
   ├── TerritoryInputManager
   ├── TerritoryColorManager
   └── ... other nodes
   ```
3. If CanvasLayer doesn't exist, add it as child of Map
4. If GameUI_01 isn't instantiated, drag GameUI_01.tscn into CanvasLayer
5. Save the scene

### Step 5: Test the Integration
1. Run Map.tscn
2. Verify UI displays:
   - Current player name with color
   - Army count (🪖)
   - Territory count (⛳)
   - Reinforcements (⏭️)
   - Turn number
   - Player position (n/x)
   - Phase with color coding
   - Context-sensitive instructions
   - Confirm button (enabled/disabled correctly)

3. Test interactions:
   - Click territories during setup → armies decrease
   - Right-click territories → undo placement
   - Confirm button → advances to next player/phase
   - Attack phase → click source then target
   - Fortify phase → click source then destination

## UI Features

### Dynamic Updates
- Player name changes color on turn switch
- Army/territory counts update on placement/conquest
- Reinforcements decrease as armies placed
- Turn number increments each round
- Player position shows current/total
- Phase label color-codes: SETUP (yellow), REINFORCEMENT (green), ATTACK (red), FORTIFY (cyan)

### Phase-Specific Behavior
- **SETUP/REINFORCEMENT**: Button disabled until all armies placed
- **ATTACK**: Button always enabled to skip
- **FORTIFY**: Button always enabled to end turn
- **GAME_OVER**: Button hidden, victory message displayed

### Selection Feedback
- Attack: Shows "Selected X. Now click enemy territory"
- Fortify: Shows "Selected X. Click connected territory"
- Error messages appear briefly then reset

## Troubleshooting

If UI doesn't appear:
- Check CanvasLayer exists in Map.tscn
- Verify GameUI_01 is instantiated under CanvasLayer
- Check script is attached to GameUI_01 root node

If UI doesn't update:
- Verify GameManager is autoload singleton at `/root/GameManager`
- Check signal connections in Output when game starts
- Verify unique names are set for all labels

If button doesn't work:
- Check button signal is connected in GameUI_01.tscn
- Verify method name is `_on_confirm_button_pressed`
- Check GameManager has `advance_phase()` and `end_turn()` methods

If errors about missing properties:
- Verify Player class has `territories_owned` array (not `territories`)
- Check GameManager has `current_player_index` and `turn_number` vars
