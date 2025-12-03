# Army Placement Controls Implementation

## Overview
Implemented comprehensive army placement and removal controls for the initial setup and reinforcement phases of the Risk game.

## Features Implemented

### 1. Army Placement Controls
- **Left-click**: Deploy 1 army on territory
- **Ctrl + Left-click**: Deploy 5 armies on territory
- Automatically caps deployment to available army reserves
- Only works on territories owned by current player
- Only active during SETUP and REINFORCEMENT phases

### 2. Army Removal Controls
- **Right-click**: Remove 1 army from territory
- **Ctrl + Right-click**: Remove 5 armies from territory
- Can only remove armies placed in the current phase (prevents removal of previously deployed armies)
- Returns armies to player's reserve pool
- Only works on territories owned by current player
- Only active during SETUP and REINFORCEMENT phases

### 3. Phase Requirements
- **Setup Phase**: All players must deploy all initial armies before advancing
  - Enforced: Cannot click "Next Player" until all armies are placed
  - Game automatically tracks which player's turn it is
  - After all players complete setup, game advances to Turn 1 Reinforcement

- **Reinforcement Phase**: Current player must deploy all reinforcement armies before attacking
  - Enforced: Cannot click "Start Attack Phase" until all armies are placed
  - Can use placement/removal controls to adjust troop distribution
  - Only armies placed in current reinforcement phase can be removed

## Technical Implementation

### Files Modified

1. **ReinforcementPhase.gd**
   - Added `armies_placed_this_phase` dictionary to track deployments per territory
   - Modified `place_army()` to accept a count parameter (1 or 5)
   - Added `remove_army()` function with count parameter (1 or 5)
   - Added `can_remove_army()` validation function
   - Connected to phase/turn change signals to reset tracking

2. **TerritoryInputManager.gd**
   - Updated `territory_clicked` signal to include `ctrl_pressed` parameter
   - Added new `territory_right_clicked` signal with `ctrl_pressed` parameter
   - Modified input event handler to detect Ctrl modifier and right-clicks

3. **Map.gd**
   - Connected to new `territory_right_clicked` signal
   - Updated `_on_territory_clicked()` to pass ctrl_pressed parameter
   - Added `_on_territory_right_clicked()` handler
   - Modified `handle_reinforcement_click()` to support count parameter
   - Added `handle_reinforcement_right_click()` for army removal

4. **GameUI.gd**
   - Updated action info text to display new controls
   - Shows: "Click +1 | Ctrl+Click +5 | Right-click -1 | Ctrl+Right-click -5"
   - Displays remaining armies to place

### Existing Enforcement
The GameManager already had enforcement in place:
- `end_turn()` checks army_reserves > 0 during SETUP phase
- `advance_phase()` checks army_reserves > 0 during REINFORCEMENT phase
- Both functions prevent progression if armies remain undeployed

## User Experience

### Setup Phase Flow
1. First player sees: "Click to place 1 army (Ctrl+Click for 5) | Right-click to remove | X armies left"
2. Player clicks territories to deploy armies
3. Can use Ctrl+Click to deploy 5 at once for faster placement
4. Can right-click to undo placements and redistribute
5. Once all armies placed, "Next Player" button becomes enabled
6. Repeat for all players
7. After all players finish, game automatically advances to Turn 1

### Reinforcement Phase Flow
1. Player receives reinforcement armies based on territories/continents
2. Sees: "Place armies: Click +1 | Ctrl+Click +5 | Right-click -1 | Ctrl+Right-click -5 | X left"
3. Player distributes armies using click controls
4. Can adjust distribution by removing/adding before advancing
5. "Start Attack Phase" button only enables when all armies are placed

## Testing Recommendations

1. **Basic Placement**: Left-click to place 1 army
2. **Bulk Placement**: Ctrl+Left-click to place 5 armies
3. **Basic Removal**: Right-click to remove 1 army (only from current phase)
4. **Bulk Removal**: Ctrl+Right-click to remove 5 armies
5. **Cap Behavior**: Try to place more armies than available in reserves
6. **Phase Enforcement**: Try to advance phase with armies remaining
7. **Turn Enforcement**: Try to end turn with armies remaining in setup
8. **Cross-Phase**: Verify armies from previous phases cannot be removed
9. **Territory Ownership**: Verify can only place on own territories
10. **Multi-player Setup**: Test full setup cycle with 2-6 players

## Future Enhancements (Optional)

- Visual feedback showing how many armies were placed in current phase per territory
- Confirmation dialog when trying to advance with armies remaining
- Hotkeys for faster army placement (number keys)
- Drag-to-distribute army placement across multiple territories
- Undo/redo system for placement decisions
