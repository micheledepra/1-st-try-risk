# Water Asset Documentation

## Overview
This water asset provides a sophisticated, customizable water surface for Godot 4 projects with animated waves, depth fade, and foam effects.

## Prerequisites
⚠️ **Important**: This asset requires the Godot project's rendering method to be set to **Forward+**. The depth fade and foam effects rely on DEPTH_TEXTURE sampling, which is only available in this renderer.

## Files
- `water_plane.tscn` - Ready-to-use water plane scene
- `water_material.tres` - Configured shader material
- `water.gdshader` - Complete water shader code

## Usage
1. Instance `water_plane.tscn` into your scene
2. Scale and position as needed
3. Adjust shader parameters in the Inspector as desired

## Shader Features
- **Animated Normal Maps**: Two procedural noise textures create realistic water surface detail
- **Vertex Displacement**: Physical wave simulation with configurable height and scale
- **Depth Fade**: Color transitions based on water depth
- **Foam Edge Detection**: Automatic foam generation at shorelines
- **Fresnel Effect**: Realistic water appearance with viewing angle-dependent coloring

## Customization
All shader parameters are exposed in the Inspector:
- **Colors**: Albedo, Deep/Shallow colors, Edge colors
- **Wave Animation**: Direction, speed, scale
- **Vertex Displacement**: Height and noise scale
- **Depth & Foam**: Beer's law, edge distance, edge scale

## Technical Details
- Mesh: 1m x 1m QuadMesh with 200x200 subdivisions
- Orientation: Face Y (horizontal surface)
- Shadow Casting: Disabled
