# Fighter Spawn System Implementation

## Overview
Implemented Ctrl+P toggle to spawn/despawn WW1 fighter plane in Map.tscn with seamless mode switching.

## Implementation Complete ✓

### 1. ModeManager.gd Changes
- **Added `FIGHTER` mode** to `GameMode` enum
- **Added state variables**:
  - `active_fighter: Node3D` - Stores active fighter reference
  - `active_fighter_camera: Camera3D` - Stores fighter's camera reference
- **Added methods**:
  - `enter_fighter_mode(fighter, camera)` - Enters fighter mode, hides territory labels
  - `exit_fighter_mode()` - Exits fighter mode, clears references, restores labels
  - `is_fighter_mode()` - Returns true if in fighter mode
  - `get_active_fighter()` - Returns active fighter reference

### 2. Map.gd Changes
- **Added Ctrl+P input handling** in `_input()` method
  - Detects `KEY_P` with `ctrl_pressed`
  - Calls `toggle_fighter_mode()`
  
- **Added `toggle_fighter_mode()` method**
  - Checks current mode and calls appropriate enter/exit function
  
- **Added `enter_fighter_mode()` method**:
  - Exits tactical mode if active (mutually exclusive modes)
  - Loads `res://Scenes/Units/Import/Fighter/FighterWW1.tscn`
  - Spawns fighter at map camera position + 50 units altitude
  - **Sets fighter rotation to match map camera's yaw** (inherits map rotation)
  - Gets fighter's embedded camera at `GLTF_SceneRootNode/Camera3D`
  - Calls `ModeManager.enter_fighter_mode()`
  - Disables strategic input
  - Transitions camera smoothly
  - Sets `Input.MOUSE_MODE_CONFINED` for flight controls
  - Updates UI to tactical mode display
  
- **Added `exit_fighter_mode()` method**:
  - Stores fighter camera reference before clearing
  - Calls `ModeManager.exit_fighter_mode()`
  - Re-enables strategic input
  - Restores map camera to initial transform
  - Transitions camera back smoothly
  - Sets `Input.MOUSE_MODE_VISIBLE`
  - Despawns fighter after 0.5s delay (waits for camera transition)
  - Updates UI back to strategic display

### 3. FighterController.gd Changes
- **Updated `_ready()` method**:
  - Moved mouse mode setup to occur for both standalone and spawned modes
  - Sets `MOUSE_MODE_CONFINED` when `_can_process_input()` returns true
  
- **Updated `_can_process_input()` method**:
  - Changed from checking `TACTICAL` mode to checking `FIGHTER` mode
  - Now returns true when `ModeManager.current_mode == GameMode.FIGHTER`

## Features Implemented

### ✓ Spawn at Map Camera Position
- Fighter spawns at `map_camera.global_position + Vector3(0, 50, 0)`
- **Fighter inherits map camera's yaw rotation** (horizontal rotation)
- Ignores pitch/roll to keep plane level

### ✓ Input Translation
- All inputs automatically routed to fighter when in FIGHTER mode
- Mouse confined to window for War Thunder-style flight controls
- FighterController processes all flight input (mouse, WASD, throttle, firing)

### ✓ Smooth Camera Transition
- Uses existing `transition_to_camera()` system
- 0.4 second smooth interpolation from map camera to fighter camera
- Reverse transition when exiting fighter mode

### ✓ Mutually Exclusive Modes
- Fighter mode automatically exits tactical mode if active
- Only one mode can be active at a time:
  - `STRATEGIC` - Default map view
  - `TACTICAL` - Tank control (Ctrl+U)
  - `FIGHTER` - Fighter control (Ctrl+P)

### ✓ Multiple Fighter Support (Architecture)
- System can support multiple fighters
- Each fighter spawned as independent instance
- Mode manager tracks active fighter reference
- Currently focuses on one fighter at a time (toggling despawns previous)

## Usage

1. **Launch game** and enter strategic mode (default map view)
2. **Press Ctrl+P** to spawn fighter:
   - Fighter appears 50 units above current map camera position
   - Fighter faces same direction as map camera
   - Camera smoothly transitions to fighter cockpit
   - Mouse cursor confined to window for flight controls
3. **Control fighter** using:
   - Mouse movement for pitch/roll (War Thunder instructor style)
   - W/S for pitch override
   - A/D for roll override
   - Q/E for yaw
   - Shift/Ctrl for throttle
   - Left mouse button to fire
4. **Press Ctrl+P again** to despawn:
   - Camera smoothly transitions back to map
   - Fighter despawns after transition
   - Returns to strategic mode

## Technical Notes

### Camera System
- Fighter camera path: `FighterWW1/GLTF_SceneRootNode/Camera3D`
- Uses existing camera transition tweening system
- Stores map camera transform for restoration

### Input Handling
- `_can_process_input()` in FighterController checks for `FIGHTER` mode
- Strategic input disabled while in fighter mode
- Mouse mode managed by Map.gd on mode entry/exit

### Mode Lifecycle
```
STRATEGIC mode (Ctrl+P) → FIGHTER mode
    ↓
- Load FighterWW1.tscn
- Position at camera + altitude
- Rotate to match camera yaw
- Enter fighter mode
- Disable strategic input
- Transition camera
- Set confined mouse

FIGHTER mode (Ctrl+P) → STRATEGIC mode
    ↓
- Store camera reference
- Exit fighter mode
- Enable strategic input
- Restore map camera
- Transition camera back
- Set visible mouse
- Despawn fighter (0.5s delay)
```

### Spawn Position Calculation
```gdscript
var spawn_pos = map_camera.global_position
spawn_pos.y += 50.0  # Altitude offset

var camera_rotation = map_camera.global_rotation
fighter.rotation = Vector3(0, camera_rotation.y, 0)  # Only yaw
```

## Future Enhancements (Not Implemented)
- Multiple simultaneous fighters
- Fighter persistence across mode switches
- Fighter selection UI
- Formation flying with AI wingmen
- Fighter-specific HUD overlay
- Respawn at last position instead of despawn
