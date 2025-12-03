# Army Placement Controls - Test Plan

## Test Scenarios

### 1. Basic Placement (Left-Click)
**Setup**: Start a new game, Setup phase
- Click on owned territory
- **Expected**: 1 army placed, reserves decrease by 1, visual updates
- Click on enemy territory  
- **Expected**: No army placed, error message

### 2. Bulk Placement (Ctrl + Left-Click)
**Setup**: Start a new game, Setup phase with 10+ armies
- Ctrl+Click on owned territory
- **Expected**: 5 armies placed, reserves decrease by 5, visual updates
- Ctrl+Click with only 3 armies remaining
- **Expected**: 3 armies placed (capped to available), reserves = 0

### 3. Basic Removal (Right-Click)
**Setup**: Setup phase, place 5 armies on territory
- Right-click on that territory
- **Expected**: 1 army removed, reserves increase by 1, visual updates
- Right-click 5 times to remove all
- Right-click again
- **Expected**: No removal, message "no armies placed this phase"

### 4. Bulk Removal (Ctrl + Right-Click)
**Setup**: Setup phase, place 10 armies on territory
- Ctrl+Right-click on that territory
- **Expected**: 5 armies removed, reserves increase by 5
- Ctrl+Right-click again
- **Expected**: 5 more armies removed, reserves increase by 5
- Ctrl+Right-click again
- **Expected**: No removal (no armies from this phase remain)

### 5. Cross-Phase Protection
**Setup**: Complete setup phase, start Turn 1 Reinforcement
- Place 3 armies on a territory during reinforcement
- Right-click that territory
- **Expected**: 1 army removed (from current reinforcement)
- Right-click twice more
- **Expected**: 2 more armies removed (from current reinforcement)
- Right-click again
- **Expected**: No removal - cannot remove setup armies

### 6. Phase Advancement Enforcement - Setup
**Setup**: Setup phase with 5 armies remaining
- Try to click "Next Player" button
- **Expected**: Button is disabled
- Place 5 armies
- **Expected**: Button becomes enabled
- Click "Next Player"
- **Expected**: Advances to next player's setup turn

### 7. Phase Advancement Enforcement - Reinforcement
**Setup**: Reinforcement phase with armies to place
- Try to click "Start Attack Phase" button
- **Expected**: Button is disabled
- Place all armies
- **Expected**: Button becomes enabled
- Click "Start Attack Phase"
- **Expected**: Advances to Attack phase

### 8. Multi-Player Setup Flow
**Setup**: 3-player game
- Player 1 places all armies, clicks "Next Player"
- **Expected**: Player 2's turn, correct army count shown
- Player 2 places all armies, clicks "Next Player"
- **Expected**: Player 3's turn
- Player 3 places all armies, clicks "Next Player"
- **Expected**: Game advances to Turn 1, Player 1 Reinforcement phase

### 9. Territory Ownership Validation
**Setup**: Any placement phase
- Click on territory you don't own
- **Expected**: No placement, error message "You don't own..."
- Ctrl+Click on territory you don't own
- **Expected**: No placement, error message

### 10. UI Updates
**Setup**: During any placement phase
- Place armies and watch UI
- **Expected**: 
  - Army reserves label updates immediately
  - Action info text shows correct count remaining
  - Button states update correctly
  - Territory visual shows army count

### 11. Edge Cases
**Test A**: Place with 0 armies in reserve
- **Expected**: Cannot place, appropriate message

**Test B**: Remove from territory with no phase armies
- **Expected**: Cannot remove, message shown

**Test C**: Rapid clicking (place/remove quickly)
- **Expected**: All actions processed correctly, no race conditions

**Test D**: Switch between territories during placement
- **Expected**: Can distribute armies across multiple territories

## Manual Testing Procedure

1. **Start Fresh Game**
   ```
   - Launch Godot project
   - Run game scene
   - Observe 3-player setup begins
   ```

2. **Test All Controls**
   ```
   - Left-click: Place 1
   - Ctrl+Left-click: Place 5
   - Right-click: Remove 1
   - Ctrl+Right-click: Remove 5
   ```

3. **Test Phase Flow**
   ```
   - Complete Player 1 setup
   - Complete Player 2 setup
   - Complete Player 3 setup
   - Verify Turn 1 starts
   - Complete reinforcement placement
   - Verify can advance to attack
   ```

4. **Test Enforcement**
   ```
   - Try to advance with armies remaining (should fail)
   - Try to remove setup armies in reinforcement (should fail)
   - Try to place on enemy territory (should fail)
   ```

## Expected Console Output Examples

**Successful Placement:**
```
Placed 1 army(s) on Alaska. Player 1 has 9 armies remaining
```

**Successful Bulk Placement:**
```
Placed 5 army(s) on Alaska. Player 1 has 4 armies remaining
```

**Successful Removal:**
```
Removed 1 army(s) from Alaska. Player 1 now has 10 armies to place
```

**Failed Removal:**
```
Cannot remove armies from Alaska - no armies placed this phase
Cannot remove army from Alaska
```

**Phase Completion:**
```
All reinforcement armies placed. You can now attack or skip to fortify.
```

## Verification Checklist

- [ ] Left-click places 1 army
- [ ] Ctrl+Left-click places 5 armies (or remaining if less)
- [ ] Right-click removes 1 army from current phase only
- [ ] Ctrl+Right-click removes 5 armies from current phase only
- [ ] Cannot place when reserves = 0
- [ ] Cannot remove armies from previous phases
- [ ] Cannot place on enemy territories
- [ ] Cannot advance setup with armies remaining
- [ ] Cannot advance reinforcement with armies remaining
- [ ] UI updates correctly show remaining armies
- [ ] Action info text shows correct controls
- [ ] Multi-player setup completes correctly
- [ ] Armies are capped to available reserves
- [ ] Visual territory updates show correct army counts
- [ ] Console messages are clear and helpful
