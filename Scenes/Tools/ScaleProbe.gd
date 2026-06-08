extends Node3D

## One-shot measurement tool: prints the native bounding-box size of the tank
## models so we can standardise the world scale against real tank dimensions.
## Run this scene directly, read the console, then delete it.

func _ready() -> void:
	await get_tree().process_frame
	var targets := [
		["res://Scenes/Units/Import/Panther/Panther.tscn", "PANTHER"],
		["res://Scenes/Units/Import/t34/t_34.tscn", "T34"],
		["res://Scenes/Units/Import/Fighter/FighterWW1.tscn", "WW1_FighterWW1"],
		["res://Scenes/Units/Import/Fighter/Fighterww_1_ph0.tscn", "WW1_ph0"],
		["res://Scenes/Units/Import/Fighter/FighterWW2/fww2_Mcc.tscn", "WW2_Mcc"],
		["res://Scenes/Units/Import/Fighter/FighterWW2/FighterWW2.tscn", "WW2_FighterWW2"],
		["res://Scenes/Units/Import/Fighter/cessna172.tscn", "cessna172"],
	]
	for t in targets:
		await _measure(t[0], t[1])
	print("SCALEPROBE_DONE")

func _measure(path: String, label: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		print("SCALEPROBE %s LOAD_FAILED" % label)
		return
	var inst: Node3D = ps.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var box: AABB = _aabb_of(inst, inst)
	var s: Vector3 = box.size
	print("SCALEPROBE %s native_size=(%.4f, %.4f, %.4f) root_scale=(%.3f, %.3f, %.3f) longest_native=%.3f" % [
		label, s.x, s.y, s.z, inst.scale.x, inst.scale.y, inst.scale.z, max(s.x, max(s.y, s.z))])
	inst.queue_free()

func _aabb_of(node: Node3D, root: Node3D) -> AABB:
	var result: AABB = AABB()
	var has: bool = false
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is VisualInstance3D:
			var local: AABB = (n as VisualInstance3D).get_aabb()
			var rel: Transform3D = root.global_transform.affine_inverse() * (n as Node3D).global_transform
			var world_box: AABB = rel * local
			if not has:
				result = world_box
				has = true
			else:
				result = result.merge(world_box)
	return result
