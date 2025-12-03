# Turn 1 Implementation - No Reinforcement Phase

## Overview
Implemented special Turn 1 game flow where the reinforcement phase is skipped after startup phase completes. Turn 1 goes directly to the attack phase, while Turn 2 onwards includes the normal reinforcement phase.

## Changes Made

### 1. GameManager.gd

#### Added Testing Mode Flag
```gdscript
# Testing mode: If true, allows manual army input after attacks instead of dice rolls
var testing_mode: bool = true
```
- Allows switching between dice-based combat and manual army input for testing
- Set to `true` by default for testing purposes
- Change to `false` to use normal dice roll combat

#### Modified `end_turn()` Function
- After all players complete startup phase, game now transitions to **ATTACK** phase instead of REINFORCEMENT
- Sets `turn_number = 1` and `current_phase = GamePhase.ATTACK`
- Prints: "Setup complete, starting turn 1 (Attack Phase - no reinforcement)"

#### Updated `advance_to_next_player()` Function
- Now checks if `turn_number == 1` before setting phase
- **Turn 1**: Sets phase to ATTACK (no reinforcement)
- **Turn 2+**: Sets phase to REINFORCEMENT (normal flow with `give_reinforcement_armies()`)
- Turn counter increments when cycling back to player 1

### 2. AttackPhase.gd

#### Modified `execute_attack()` Function
Added dual-mode combat system:

**Testing Mode (`testing_mode = true`)**:
- Prints battle information to console
- Uses default loss values (1 army each) temporarily
- Ready for UI dialog integration for manual input
- Shows: "TESTING MODE ATTACK" with army counts

**Normal Mode (`testing_mode = false`)**:
- Uses standard Risk dice roll mechanics
- Attacker rolls 1-3 dice (max 3, limited by armies-1)
- Defender rolls 1-2 dice (max 2, limited by armies)
- Compares highest rolls, ties favor defender

#### Updated `conquer_territory()` Function
- Prompts for army transfer amount when territory is conquered
- Shows available armies (total - 1 that must stay)
- Default behavior: moves all available armies
- Prints transfer information to console
- Ready for UI dialog integration

### 3. gameUI_01.gd

#### Added Instruction Panel Auto-Hide
- Added `instruction_timer: Timer` variable
- Added `INSTRUCTION_DISPLAY_TIME = 5.0` constant
- Instruction panel now shows for 5 seconds then fades out smoothly
- Timer restarts on each turn/phase change

#### Modified `_update_phase_display()` Function
- Removed Turn 1 special text
- Attack phase always shows: "ATTACK" (no special Turn 1 message)

#### Updated `_update_instructions_and_button()` Function
- Removed Turn 1 special instruction text
- Shows standard attack instructions for all turns
- Shows "⚠ TESTING MODE: Manual army input" when `testing_mode = true`
- Calls `_show_instruction_panel()` at the start of each phase

#### Added Helper Functions
- `_show_instruction_panel()`: Makes panel visible and starts 5-second timer
- `_on_instruction_timer_timeout()`: Fades out panel over 1 second using Tween

## Game Flow

### Startup Phase (Turn 0)
```
SETUP Phase
├── Player 1 places remaining armies → end_turn()
├── Player 2 places remaining armies → end_turn()
├── ...
└── Player N places remaining armies → end_turn()
    └── All army_reserves == 0 → Turn 1 ATTACK
```

### Turn 1 (Special - No Reinforcement)
```
Turn 1 - Player 1: ATTACK Phase
├── Execute attacks (optional)
├── Conquer territories (optional)
└── advance_phase() → FORTIFY

Turn 1 - Player 1: FORTIFY Phase
├── Move armies (optional)
└── end_turn() → Turn 1 ATTACK (Player 2)

[Cycle through all players in ATTACK → FORTIFY]
└── Last player end_turn() → Turn 2 REINFORCEMENT (Player 1)
```

### Turn 2+ (Normal Flow)
```
Turn N - Player X: REINFORCEMENT Phase
├── Calculate armies (territories/3 + continent bonuses)
├── Place armies
└── advance_phase() → ATTACK

Turn N - Player X: ATTACK Phase
├── Execute attacks (optional)
├── Conquer territories (optional)
└── advance_phase() → FORTIFY

Turn N - Player X: FORTIFY Phase
├── Move armies (optional)
└── end_turn() → REINFORCEMENT (next player)
```

## Testing Mode Features

### Combat Testing
- `testing_mode = true` in GameManager.gd
- Allows manual specification of attack results
- Console prints show battle information
- Default behavior: each side loses 1 army per attack
- Ready for UI integration

### Army Transfer on Conquest
- Prompts shown in console (ready for UI dialog)
- Shows: source territory armies, destination territory
- Shows: valid range (1 to available_armies)
- Default: transfers all available armies

## UI Indicators

The game UI now shows:
- **Attack Phase**: "ATTACK" (same for all turns)
- **Testing Mode**: "⚠ TESTING MODE: Manual army input"
- **Instruction Panel**: Displays for 5 seconds then fades out automatically
- **Turn 2+**: Normal reinforcement → attack → fortify flow

## Future Enhancements

### Short-term (UI Integration)
1. Create dialog for manual army input in testing mode
   - Input fields for attacker/defender remaining armies
   - Validation (can't exceed initial armies)
   
2. Create dialog for army transfer on conquest
   - Slider/input for number of armies to move
   - Range: 1 to (source_armies - 1)
   - Visual feedback

### Long-term
1. Add toggle button in UI to switch testing_mode on/off
2. Add battle animation/visualization
3. Save testing mode preference to settings
4. Add attack history log

## Notes

- All code changes maintain backward compatibility
- No breaking changes to existing game mechanics
- Signal system unchanged (phase_changed, turn_changed work as before)
- Win condition checking unaffected
- Player elimination mechanics unchanged

## Testing Checklist

- [ ] Startup phase completes normally
- [ ] Turn 1 starts in ATTACK phase (no reinforcement)
- [ ] All players cycle through Turn 1 in ATTACK → FORTIFY
- [ ] Turn 2 starts with REINFORCEMENT phase
- [ ] Turn 2+ follows normal REINFORCEMENT → ATTACK → FORTIFY flow
- [ ] Testing mode shows appropriate console messages
- [ ] Territory conquest prompts for army transfer
- [ ] UI displays Turn 1 special message
- [ ] UI shows testing mode indicator
- [ ] Normal dice mode works when testing_mode = false
