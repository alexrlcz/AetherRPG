shader_type spatial;
// Flagstone dungeon floor. UV is the floor's position on the straight level
// grid in metres (DungeonBuilder sets it before the warp bends the mesh), so
// the courses of stones follow curved rooms and corridors.
// Stones are `stone_size` (m) rectangles in rows shifted by a random amount,
// each slightly tinted, with sunken dark mortar between them and large-scale
// grime from `noise_texture`.

uniform vec4 stone_color : source_color = vec4(0.47, 0.44, 0.4, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.2, 0.18, 0.16, 1.0);
uniform sampler2D noise_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 stone_size = vec2(1.25, 0.85);
uniform float mortar_width = 0.035;
uniform float tint_variation : hint_range(0.0, 1.0) = 0.22;
uniform float grime_scale = 0.07;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV / stone_size;
	float row = floor(p.y);
	p.x += hash(vec2(row, 7.3));
	vec2 stone = floor(p);
	vec2 f = fract(p);
	vec2 to_edge = min(f, 1.0 - f) * stone_size;
	float edge = min(to_edge.x, to_edge.y);
	float mortar = 1.0 - smoothstep(mortar_width * 0.5, mortar_width, edge);
	float tint = 1.0 + (hash(stone + row * 13.0) - 0.5) * tint_variation;
	float grime = texture(noise_texture, UV * grime_scale).r;
	float detail = texture(noise_texture, UV * 0.6 + stone * 0.37).r;
	vec3 base = stone_color.rgb * tint * grime * mix(0.85, 1.05, detail);
	ALBEDO = mix(base, mortar_color.rgb, mortar);
	ROUGHNESS = roughness_value;
	// Mortar lines read as grooves: tip the normal toward the stone's centre.
	vec2 grad = vec2(f.x < 0.5 ? -1.0 : 1.0, f.y < 0.5 ? -1.0 : 1.0);
	vec2 tilt = (to_edge.x < to_edge.y ? vec2(grad.x, 0.0) : vec2(0.0, grad.y)) * mortar * 0.35;
	NORMAL_MAP = vec3(-tilt * 0.5 + 0.5, 1.0);
}
