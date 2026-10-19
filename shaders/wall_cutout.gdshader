shader_type spatial;
// Stone wall that turns see-through where it stands between the camera and
// the player. IsoCameraRig sets the global parameters every frame
// (project.godot [shader_globals]); cutout_radius 0 disables the hole.
// The hole is dithered (discard, not alpha), so walls stay in the opaque pass.
// Albedo: `albedo` darkened by a world-space triplanar noise texture, like
// DungeonBuilder's other stone materials.

global uniform vec3 cutout_camera;
global uniform vec3 cutout_target;
global uniform float cutout_radius;

uniform vec4 albedo : source_color = vec4(0.42, 0.39, 0.37, 1.0);
uniform sampler2D noise_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
// Fraction of the radius over which the hole's edge fades in.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.4;
// Wall closer than this (m) to the target along the line is never cut, so
// the wall right behind a character pressed against it stays solid.
uniform float target_margin = 0.4;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float cutout_amount() {
	vec3 line = cutout_target - cutout_camera;
	float len = length(line);
	if (cutout_radius <= 0.0 || len < 0.001) {
		return 0.0;
	}
	vec3 dir = line / len;
	vec3 rel = world_pos - cutout_camera;
	float t = dot(rel, dir);
	if (t <= 0.0 || t >= len - target_margin) {
		return 0.0;
	}
	float perp = length(rel - dir * t);
	return 1.0 - smoothstep(cutout_radius * (1.0 - edge_softness), cutout_radius, perp);
}

void fragment() {
	float cut = cutout_amount();
	if (cut > 0.0) {
		// Interleaved gradient noise: a stable per-pixel threshold.
		float threshold = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (cut > threshold) {
			discard;
		}
	}
	vec3 blend = abs(world_normal);
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec3 p = world_pos * uv_scale;
	vec3 tex = texture(noise_texture, p.zy).rgb * blend.x
		+ texture(noise_texture, p.xz).rgb * blend.y
		+ texture(noise_texture, p.xy).rgb * blend.z;
	ALBEDO = albedo.rgb * tex;
	ROUGHNESS = roughness_value;
}
