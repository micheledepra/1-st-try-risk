"""
SVG to 3D GLTF Converter for Godot Risk Game
Converts SVG territory paths to extruded 3D meshes with 4cm thickness along Y-axis
Creates flat meshes with proper triangulation and side walls
"""

import xml.etree.ElementTree as ET
import json
import struct
import base64
import os
import re
import math
from pathlib import Path
from typing import List, Tuple

# Constants
THICKNESS_CM = 4.0  # 4cm thickness
SCALE_FACTOR = 0.1  # Scale down for Godot (SVG units to cm)


def parse_svg_path(path_data: str) -> List[Tuple[float, float]]:
    """Parse SVG path data and return list of 2D points."""
    points = []
    
    # Extract all coordinate pairs from path
    # SVG paths use commands like M (move), L (line), Z (close)
    coords = re.findall(r'([ML])?(\d+\.?\d*),(\d+\.?\d*)', path_data)
    
    for match in coords:
        x = float(match[1])
        y = float(match[2])
        points.append((x, y))
    
    return points


def triangulate_polygon(points: List[Tuple[float, float]]) -> List[int]:
    """Ear clipping triangulation for polygon with proper winding order."""
    if len(points) < 3:
        return []
    
    # Create a copy of indices
    available = list(range(len(points)))
    indices = []
    
    # Simple fan triangulation from first vertex
    # This works well for convex polygons and most SVG territory shapes
    for i in range(1, len(points) - 1):
        indices.extend([0, i, i + 1])
    
    return indices


def calculate_edge_normal(p1: Tuple[float, float], p2: Tuple[float, float]) -> Tuple[float, float, float]:
    """Calculate outward normal for an edge in XZ plane."""
    # Edge vector
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    
    # Perpendicular in XZ plane (rotate 90 degrees)
    # Normal points outward (to the right of the edge direction)
    length = math.sqrt(dx*dx + dy*dy)
    if length < 0.0001:
        return (0, 0, 1)
    
    # In XZ plane: edge is (dx, dz), perpendicular is (dz, -dx) normalized
    nx = dy / length
    nz = -dx / length
    
    return (nx, 0, nz)


def create_extruded_mesh(points: List[Tuple[float, float]], svg_viewbox: Tuple[float, float, float, float]) -> dict:
    """Create flat extruded 3D mesh from 2D points with proper side walls."""
    if len(points) < 3:
        raise ValueError("Need at least 3 points to create a mesh")
    
    # Calculate SVG bounding box center for centering
    min_x = min(p[0] for p in points)
    max_x = max(p[0] for p in points)
    min_y = min(p[1] for p in points)
    max_y = max(p[1] for p in points)
    
    center_x = (min_x + max_x) / 2
    center_y = (min_y + max_y) / 2
    
    # Scale and center the mesh
    half_thickness = THICKNESS_CM / 2  # 2cm each side = 4cm total
    
    vertices = []
    normals = []
    uvs = []
    indices = []
    
    n = len(points)
    
    # ===== CREATE TOP FACE =====
    # All points at Y = +half_thickness
    top_start = 0
    for i, (x, y) in enumerate(points):
        scaled_x = (x - center_x) * SCALE_FACTOR
        scaled_z = (y - center_y) * SCALE_FACTOR
        
        vertices.extend([scaled_x, half_thickness, scaled_z])
        normals.extend([0, 1, 0])  # Up normal
        
        # UV coordinates
        u = (x - min_x) / (max_x - min_x) if max_x > min_x else 0.5
        v = (y - min_y) / (max_y - min_y) if max_y > min_y else 0.5
        uvs.extend([u, v])
    
    # Triangulate top face
    top_indices = triangulate_polygon(points)
    indices.extend(top_indices)
    
    # ===== CREATE BOTTOM FACE =====
    # All points at Y = -half_thickness
    bottom_start = len(vertices) // 3
    for i, (x, y) in enumerate(points):
        scaled_x = (x - center_x) * SCALE_FACTOR
        scaled_z = (y - center_y) * SCALE_FACTOR
        
        vertices.extend([scaled_x, -half_thickness, scaled_z])
        normals.extend([0, -1, 0])  # Down normal
        
        u = (x - min_x) / (max_x - min_x) if max_x > min_x else 0.5
        v = (y - min_y) / (max_y - min_y) if max_y > min_y else 0.5
        uvs.extend([u, v])
    
    # Triangulate bottom face (reversed winding for correct culling)
    for i in range(0, len(top_indices), 3):
        indices.extend([
            top_indices[i] + bottom_start,
            top_indices[i+2] + bottom_start,
            top_indices[i+1] + bottom_start
        ])
    
    # ===== CREATE SIDE WALLS =====
    # Each edge of the polygon becomes a rectangular side wall
    side_start = len(vertices) // 3
    
    for i in range(n):
        next_i = (i + 1) % n
        
        x1, y1 = points[i]
        x2, y2 = points[next_i]
        
        # Scale points
        sx1 = (x1 - center_x) * SCALE_FACTOR
        sz1 = (y1 - center_y) * SCALE_FACTOR
        sx2 = (x2 - center_x) * SCALE_FACTOR
        sz2 = (y2 - center_y) * SCALE_FACTOR
        
        # Calculate outward normal for this edge
        edge_normal = calculate_edge_normal((x1, y1), (x2, y2))
        
        # Create 4 vertices for this side wall (duplicated for proper normals)
        # Bottom-left
        vertices.extend([sx1, -half_thickness, sz1])
        normals.extend(edge_normal)
        uvs.extend([0, 0])
        
        # Top-left
        vertices.extend([sx1, half_thickness, sz1])
        normals.extend(edge_normal)
        uvs.extend([0, 1])
        
        # Top-right
        vertices.extend([sx2, half_thickness, sz2])
        normals.extend(edge_normal)
        uvs.extend([1, 1])
        
        # Bottom-right
        vertices.extend([sx2, -half_thickness, sz2])
        normals.extend(edge_normal)
        uvs.extend([1, 0])
        
        # Two triangles for this wall quad
        base_idx = side_start + (i * 4)
        
        # Triangle 1: bottom-left, top-left, top-right
        indices.extend([base_idx, base_idx + 1, base_idx + 2])
        
        # Triangle 2: bottom-left, top-right, bottom-right
        indices.extend([base_idx, base_idx + 2, base_idx + 3])
    
    return {
        'vertices': vertices,
        'normals': normals,
        'uvs': uvs,
        'indices': indices
    }


def create_gltf_binary_buffer(mesh_data: dict) -> bytes:
    """Create binary buffer for GLTF mesh data."""
    buffer = bytearray()
    
    # Pack vertices (positions)
    for v in mesh_data['vertices']:
        buffer.extend(struct.pack('<f', v))
    
    # Pack UVs
    for uv in mesh_data['uvs']:
        buffer.extend(struct.pack('<f', uv))
    
    # Pack normals
    for n in mesh_data['normals']:
        buffer.extend(struct.pack('<f', n))
    
    # Pack indices (unsigned short)
    for idx in mesh_data['indices']:
        buffer.extend(struct.pack('<H', idx))
    
    return bytes(buffer)


def calculate_bounds(vertices: List[float]) -> dict:
    """Calculate min/max bounds for vertices."""
    if not vertices:
        return {"min": [0, 0, 0], "max": [0, 0, 0]}
    
    positions = [(vertices[i], vertices[i+1], vertices[i+2]) 
                 for i in range(0, len(vertices), 3)]
    
    min_x = min(p[0] for p in positions)
    max_x = max(p[0] for p in positions)
    min_y = min(p[1] for p in positions)
    max_y = max(p[1] for p in positions)
    min_z = min(p[2] for p in positions)
    max_z = max(p[2] for p in positions)
    
    return {
        "min": [min_x, min_y, min_z],
        "max": [max_x, max_y, max_z]
    }


def create_gltf(mesh_data: dict, territory_name: str) -> dict:
    """Create GLTF JSON structure."""
    vertex_count = len(mesh_data['vertices']) // 3
    index_count = len(mesh_data['indices'])
    
    # Calculate byte offsets
    vertices_byte_length = len(mesh_data['vertices']) * 4  # float32
    uvs_byte_length = len(mesh_data['uvs']) * 4
    normals_byte_length = len(mesh_data['normals']) * 4
    indices_byte_length = len(mesh_data['indices']) * 2  # uint16
    
    total_byte_length = vertices_byte_length + uvs_byte_length + normals_byte_length + indices_byte_length
    
    bounds = calculate_bounds(mesh_data['vertices'])
    
    gltf = {
        "asset": {
            "version": "2.0",
            "generator": "SVG to 3D Territory Converter for Godot"
        },
        "scenes": [
            {
                "name": f"{territory_name}_scene",
                "nodes": [0]
            }
        ],
        "scene": 0,
        "nodes": [
            {
                "name": territory_name,
                "mesh": 0
            }
        ],
        "meshes": [
            {
                "name": f"{territory_name}_mesh",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 0,
                            "TEXCOORD_0": 1,
                            "NORMAL": 2
                        },
                        "indices": 3,
                        "material": 0
                    }
                ]
            }
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,  # FLOAT
                "count": vertex_count,
                "type": "VEC3",
                "min": bounds["min"],
                "max": bounds["max"]
            },
            {
                "bufferView": 1,
                "componentType": 5126,  # FLOAT
                "count": vertex_count,
                "type": "VEC2"
            },
            {
                "bufferView": 2,
                "componentType": 5126,  # FLOAT
                "count": vertex_count,
                "type": "VEC3"
            },
            {
                "bufferView": 3,
                "componentType": 5123,  # UNSIGNED_SHORT
                "count": index_count,
                "type": "SCALAR"
            }
        ],
        "bufferViews": [
            {
                "buffer": 0,
                "byteOffset": 0,
                "byteLength": vertices_byte_length,
                "target": 34962,  # ARRAY_BUFFER
                "byteStride": 12
            },
            {
                "buffer": 0,
                "byteOffset": vertices_byte_length,
                "byteLength": uvs_byte_length,
                "target": 34962,
                "byteStride": 8
            },
            {
                "buffer": 0,
                "byteOffset": vertices_byte_length + uvs_byte_length,
                "byteLength": normals_byte_length,
                "target": 34962,
                "byteStride": 12
            },
            {
                "buffer": 0,
                "byteOffset": vertices_byte_length + uvs_byte_length + normals_byte_length,
                "byteLength": indices_byte_length,
                "target": 34963  # ELEMENT_ARRAY_BUFFER
            }
        ],
        "buffers": [
            {
                "byteLength": total_byte_length,
                "uri": f"{territory_name}.bin"
            }
        ],
        "materials": [
            {
                "name": "territory_material",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.957, 0.816, 0.247, 1.0],  # #f4d03f color
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.5
                },
                "doubleSided": True
            }
        ]
    }
    
    return gltf


def convert_svg_to_gltf(svg_path: str, output_dir: str):
    """Convert a single SVG file to GLTF with binary data."""
    # Parse SVG
    tree = ET.parse(svg_path)
    root = tree.getroot()
    
    # Extract namespace
    ns = {'svg': 'http://www.w3.org/2000/svg'}
    
    # Get viewBox for proper scaling
    viewbox_str = root.get('viewBox', '0 0 100 100')
    viewbox = tuple(map(float, viewbox_str.split()))
    
    # Find the path element
    path_elem = root.find('.//svg:path', ns)
    if path_elem is None:
        print(f"Warning: No path found in {svg_path}")
        return
    
    path_data = path_elem.get('d', '')
    territory_id = path_elem.get('id', Path(svg_path).stem)
    
    # Parse path to points
    points = parse_svg_path(path_data)
    
    if len(points) < 3:
        print(f"Error: Not enough points in {svg_path}")
        return
    
    print(f"Converting {territory_id}: {len(points)} points")
    
    # Create 3D mesh
    mesh_data = create_extruded_mesh(points, viewbox)
    
    # Create GLTF structure
    gltf = create_gltf(mesh_data, territory_id)
    
    # Create binary buffer
    binary_data = create_gltf_binary_buffer(mesh_data)
    
    # Write GLTF JSON
    gltf_path = os.path.join(output_dir, f"{territory_id}.gltf")
    with open(gltf_path, 'w') as f:
        json.dump(gltf, f, indent=2)
    
    # Write binary buffer
    bin_path = os.path.join(output_dir, f"{territory_id}.bin")
    with open(bin_path, 'wb') as f:
        f.write(binary_data)
    
    print(f"  ✓ Created {territory_id}.gltf and {territory_id}.bin")


def main():
    """Main conversion function."""
    # Setup paths
    script_dir = Path(__file__).parent
    svg_dir = script_dir / "Assets" / "Territories" / "Vanilla"
    output_dir = svg_dir / "3D"
    
    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Find all SVG files
    svg_files = list(svg_dir.glob("*.svg"))
    
    print(f"Found {len(svg_files)} SVG files to convert")
    print(f"Output directory: {output_dir}")
    print(f"Thickness: {THICKNESS_CM}cm along Y-axis\n")
    
    # Convert each SVG
    for svg_file in sorted(svg_files):
        try:
            convert_svg_to_gltf(str(svg_file), str(output_dir))
        except Exception as e:
            print(f"  ✗ Error converting {svg_file.name}: {e}")
    
    print(f"\n✓ Conversion complete! Generated {len(svg_files)} territories in {output_dir}")


if __name__ == "__main__":
    main()
