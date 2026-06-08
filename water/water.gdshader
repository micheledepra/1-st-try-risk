shader_type spatial;

// Basic Properties & Colors
uniform vec4 albedo : source_color = vec4(0.0, 0.3215, 0.4313, 1.0);
uniform vec4 albedo2 : source_color = vec4(0.0, 0.4745, 0.7647, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.0;

// Normal Maps & Animation
uniform sampler2D texture_normal : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D texture_normal2 : source_color,filter_linear_mipmap,repeat_enable;
uniform vec2 wave_direction = vec2(1.0, 0.0);
uniform vec2 wave_direction2 = vec2(0.0, 1.0);
uniform float time_scale = 0.025;

// Vertex Displacement
uniform sampler2D wave : source_color,filter_linear_mipmap,repeat_enable;
uniform float noise_scale = 5.0;
uniform float height_scale = 0.1;

// Depth Fade
uniform vec4 deep_color : source_color = vec4(0.0, 0.3215, 0.4313, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.0, 0.4745, 0.7647, 1.0);
uniform float beers_law = 1.0;
uniform float depth_offset = 0.0;

// Foam Edge Detection
uniform vec4 edge_color_near : source_color = vec4(1.0);
uniform vec4 edge_color_far : source_color = vec4(1.0);
uniform float edge_scale = 0.1;
uniform float near_distance = 0.1;

varying vec3 world_pos;
varying float height;

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow(1.0 - dot(normal, view), amount);
}

float edge(float depth, float near, float scale) {
    return clamp(1.0 - (depth - near) / scale, 0.0, 1.0);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec2 noise_uv = world_pos.xz / noise_scale;
    noise_uv += TIME * time_scale;
    height = texture(wave, noise_uv).r;
    VERTEX.y += height * height_scale;
}

void fragment() {
    // Get Depth from Viewport
    float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    depth = PROJECTION_MATRIX[3][2] / (depth + PROJECTION_MATRIX[2][2]);
    depth = depth + VERTEX.z;
    depth = exp(-depth * beers_law) - depth_offset;
    depth = clamp(depth, 0.0, 1.0);

    // Calculate Depth & Edge Colors
    vec4 depth_color = mix(deep_color, shallow_color, depth);
    float edge_val = edge(depth, near_distance, edge_scale);
    vec4 edge_color = mix(edge_color_far, edge_color_near, edge_val);

    // Animate and Blend Normal Maps
    vec2 uv_time_offset = (wave_direction * TIME * time_scale);
    vec2 uv_time_offset2 = (wave_direction2 * TIME * time_scale);
    vec3 normal_map = texture(texture_normal, world_pos.xz + uv_time_offset).rgb;
    vec3 normal_map2 = texture(texture_normal2, world_pos.xz + uv_time_offset2).rgb;
    vec3 normal_blend = mix(normal_map, normal_map2, 0.5);

    // Fresnel Effect
    float fresnel_val = fresnel(5.0, NORMAL, VIEW);
    vec4 fresnel_color = mix(albedo, albedo2, fresnel_val);

    // Combine and Set Final Albedo
    ALBEDO = mix(depth_color, edge_color, edge_val).rgb;
    ALBEDO = mix(ALBEDO, fresnel_color.rgb, fresnel_val);
    
    METALLIC = metallic;
    ROUGHNESS = roughness;
    NORMAL_MAP = normal_blend;
}
