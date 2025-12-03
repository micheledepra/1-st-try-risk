# Physics-Free Unit System

## Overview
All decorative units on territories now use a **completely physics-free** approach, eliminating all physics overhead and significantly improving performance.

## Key Changes

### 1. **Zero Physics Components**
- All RigidBody3D, StaticBody3D, CharacterBody3D nodes removed
- All CollisionShape3D, CollisionPolygon3D nodes removed  
- All Area3D nodes removed
- All AnimatableBody3D nodes removed

### 2. **No Scripts or Processing**
- All scripts (including TankController) completely removed from decorative units
- All processing disabled: `_process()`, `_physics_process()`, `_input()`, `_unhandled_input()`
- Process mode set to `PROCESS_MODE_DISABLED` on entire tree
- Zero CPU overhead from script execution

### 3. **Parent-Child Transform System**
Units are positioned by:
- **Snapping to territory center** - calculated once from territory mesh AABB
- **Parenting to territory** - units become direct children of territory nodes
- **Automatic movement** - units inherit ALL territory transforms, rotations, and animations
- **Formation-based offset** - pre-designed formations provide relative positions

### 4. **Benefits**
- ✅ **Massive performance improvement** - no physics simulation whatsoever
- ✅ **Automatic animation following** - units move perfectly with territory animations
- ✅ **Simpler code** - no physics update loops or position syncing needed
- ✅ **Predictable behavior** - pure transform hierarchy, no physics jitter
- ✅ **Reduced memory** - no physics bodies, collision shapes, or processing overhead

### 5. **Architecture**

#### Decorative Units (Visual Only)
- **Source**: Object pool (150 per unit type)
- **Components**: Node3D + MeshInstance3D only
- **Scripts**: None (completely removed)
- **Physics**: None (completely removed)
- **Processing**: Disabled (PROCESS_MODE_DISABLED)
- **Purpose**: Visual representation of armies (1-9 units)

#### Controllable Units (Tactical Mode)
- **Source**: Full unit scene instantiated fresh
- **Components**: Node3D + MeshInstance3D + TankController script + Camera3D
- **Scripts**: TankController (for player control)
- **Physics**: None (TankController uses direct transform manipulation)
- **Processing**: Enabled (for input and movement)
- **Purpose**: Player-controlled unit in tactical mode

## Implementation Details

### Unit Creation Process
```gdscript
func create_static_unit(unit_scene: PackedScene) -> Node3D:
    1. Instantiate unit from scene
    2. Remove ALL scripts from entire node tree
    3. Remove ALL physics components recursively
    4. Disable ALL processing on entire tree
    5. Return pure visual Node3D with meshes only
```

### Physics Component Removal
```gdscript
func remove_physics_components(node: Node):
    Recursively removes:
    - RigidBody3D
    - StaticBody3D  
    - CharacterBody3D
    - AnimatableBody3D
    - CollisionShape3D
    - CollisionPolygon3D
    - Area3D
```

### Processing Disablement
```gdscript
func disable_all_processing(node: Node):
    For entire node tree:
    - set_process(false)
    - set_physics_process(false)
    - set_process_input(false)
    - set_process_unhandled_input(false)
    - process_mode = PROCESS_MODE_DISABLED
```

### Unit Positioning
```gdscript
func spawn_territory_units():
    1. Calculate territory center from mesh AABB
    2. Get formation layout for unit count (1-9)
    3. For each unit in formation:
        a. Get unit from pool
        b. Set position = territory_center + formation_offset + height_offset
        c. Set rotation from formation data
        d. Apply player color to materials
        e. **Parent to territory** (automatic transform inheritance)
        f. Set scale (compensating for territory scale)
        g. Make visible
```

## File Modified

### `Scripts/Map/TerritoryUnitManager.gd`
**Enhanced Functions:**
- `create_static_unit()` - Now removes scripts and disables processing
- `remove_physics_components()` - Now removes Area3D and AnimatableBody3D
- **NEW** `remove_all_scripts()` - Recursively removes all scripts
- **NEW** `disable_all_processing()` - Recursively disables all processing

**Updated Documentation:**
- Header comments explain physics-free approach
- Inline comments explain parent-child transform system
- Print messages indicate "zero physics overhead"

## Testing Recommendations

1. **Visual Verification**
   - Units should appear correctly positioned on territories
   - Units should move smoothly with territory animations
   - Formations should maintain proper spacing and rotation

2. **Performance Verification**
   - Monitor FPS with many units on screen
   - Check physics server usage (should be minimal/zero for decorative units)
   - Profile script execution time (should be zero for decorative units)

3. **Functional Verification**
   - Army count changes should update unit visuals correctly
   - Switching to tactical mode should spawn controllable unit properly
   - Pooling should work correctly (units reused efficiently)

## Notes

- **Pooled units** are decorative only - completely static, no physics, no scripts
- **Controllable units** are separate instances - have scripts and can be controlled
- Parent-child relationship means units automatically follow ANY territory transform changes
- No manual position updates needed - Godot's scene tree handles it automatically
- This is the most efficient approach possible for static/decorative 3D objects
