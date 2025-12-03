extends Area3D

## Lightweight hitbox for decorative units
## Provides collision shape for projectile detection
## Hit handling is done by Projectile.gd - this script only provides the hitbox Area3D

func _ready() -> void:
	# Disable frame processing for zero overhead
	# Collision detection still works - Projectile.gd handles the hit logic
	set_process(false)
	set_physics_process(false)
