@tool
extends EditorScript

# Simple border generator using mesh outline detection
# This creates a visible line around each territory's perimeter

func _run():
	print("=== Simplified Border Generator ===\n")
	
	var map_scene = load("res://Scenes/Map.tscn")
	if not map_scene:
		print("ERROR: Cannot load Map.tscn")
		return
	
	var map_root = map_scene.instantiate()
	var continents = map_root.get_node_or_null("Continents")
	
	if not continents:
		print("ERROR: No Continents node")
		map_root.queue_free()
		return
	
	var success = 0
	var total = 0
	
	for continent in continents.get_children():
		for territory in continent.get_children():
			total += 1
			print("Processing: ", territory.name)
			
			if add_simple_border(territory):
				success += 1
				print("  ✓")
			else:
				print("  ✗")
	
	# Save
	var packed = PackedScene.new()
	packed.pack(map_root)
	ResourceSaver.save(packed, "res://Scenes/Map.tscn")
	
	map_root.queue_free()
	print("\nDone: ", success, "/", total)

func add_simple_border(territory: Node) -> bool:
	# Remove old border if exists
	var old = territory.get_node_or_null("Border")
	if old:
		old.free()
	
	# Find mesh
	var mesh_node: MeshInstance3D = null
	for child in territory.get_children():
		if child is MeshInstance3D:
			mesh_node = child
			break
	
	if not mesh_node or not mesh_node.mesh:
		return false
	
	# Create border using mesh outline
	var border = create_outline_mesh(mesh_node.mesh)
	if not border:
		return false
	
	var border_node = MeshInstance3D.new()
	border_node.name = "Border"
	border_node.mesh = border
	border_node.material_override = create_white_unshaded_material()
	border_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	territory.add_child(border_node)
	border_node.owner = map_root_from_territory(territory)
	
	return true

func create_outline_mesh(source_mesh: Mesh) -> ArrayMesh:
	# Extract mesh data
	var mdt = MeshDataTool.new()
	var err = mdt.create_from_surface(source_mesh, 0)
	if err != OK:
		return null
	
	# Find boundary edges (edges that belong to only one face)
	var edge_faces = {}  # edge_key -> face_count
	
	for face_idx in range(mdt.get_face_count()):
		var v0 = mdt.get_face_vertex(face_idx, 0)
		var v1 = mdt.get_face_vertex(face_idx, 1)
		var v2 = mdt.get_face_vertex(face_idx, 2)
		
		# Register three edges
		count_edge(edge_faces, v0, v1)
		count_edge(edge_faces, v1, v2)
		count_edge(edge_faces, v2, v0)
	
	# Find boundary edges
	var boundary_edges = []
	for edge_key in edge_faces:
		if edge_faces[edge_key] == 1:  # Used by only 1 face = boundary
			var parts = edge_key.split("|")
			boundary_edges.append([int(parts[0]), int(parts[1])])
	
	if boundary_edges.is_empty():
		return null
	
	# Create line mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	
	var vertex_idx = 0
	for edge in boundary_edges:
		var v0 = mdt.get_vertex(edge[0])
		var v1 = mdt.get_vertex(edge[1])
		
		# Lift slightly to prevent z-fighting
		v0.y += 0.02
		v1.y += 0.02
		
		vertices.append(v0)
		vertices.append(v1)
		indices.append(vertex_idx)
		indices.append(vertex_idx + 1)
		vertex_idx += 2
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	
	return mesh

func count_edge(edge_map: Dictionary, v0: int, v1: int):
	var key = str(min(v0, v1)) + "|" + str(max(v0, v1))
	edge_map[key] = edge_map.get(key, 0) + 1

func create_white_unshaded_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 2.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func map_root_from_territory(territory: Node) -> Node:
	# Territory -> Continent -> Continents -> Map
	var continent = territory.get_parent()
	if not continent:
		return null
	var continents = continent.get_parent()
	if not continents:
		return null
	return continents.get_parent()
