shader_type spatial;
render_mode cull_disabled;
// Dungeon wall (and anything mounted on or standing like one: door frames,
// torches, pillars) that gets out of the camera's way. IsoCameraRig sets the
// global parameters every frame (project.godot [shader_globals]):
// - Front cutaway: everything on the camera's side of the target, within
//   `cutout_front_width` (m) to either side of the camera's view line, is
//   cut down to `cutout_stub_height` (m), so the near walls of a room read
//   as low stubs and the far walls stay full height. 0 width = off.
// - Hole: within `cutout_radius` (m) of the camera-to-target line, cut
//   entirely (also below the stub). 0 = off.
// Cuts are dithered (discard, not alpha), so walls stay in the opaque pass.
// Faces seen from behind (inside a cut wall) draw as dark rock, so a cut
// wall looks solid.
// Albedo: `albedo` darkened by a world-space triplanar noise texture (if
// `use_noise`), and darker toward the top (`top_darkening`) so tall walls
// fade into the gloom.

global uniform vec3 cutout_camera;
global uniform vec3 cutout_target;
global uniform float cutout_radius;
global uniform float cutout_front_width;
global uniform float cutout_stub_height;

uniform vec4 albedo : source_color = vec4(0.42, 0.39, 0.37, 1.0);
uniform bool use_noise = true;
uniform sampler2D noise_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// Albedo multiplier at `top_height` (m) and above, from 1.0 at `fade_start`.
uniform float top_darkening : hint_range(0.0, 1.0) = 0.45;
uniform float fade_start = 1.2;
uniform float top_height = 4.2;
uniform vec4 interior_color : source_color = vec4(0.07, 0.06, 0.06, 1.0);
// Fraction of the hole radius over which its edge fades in.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.4;
// Geometry closer than this (m) to the target (horizontally toward the
// camera, or along the hole's line) is never cut, so a wall right behind a
// character pressed against it stays solid.
uniform float target_margin = 0.4;
// Metres over which the front cutaway fades in, toward the camera and at its
// sides.
uniform float front_softness = 0.5;


varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hole_amount() {
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

float front_amount() {
	if (cutout_front_width <= 0.0 || world_pos.y <= cutout_stub_height) {
		return 0.0;
	}
	vec2 to_camera = cutout_camera.xz - cutout_target.xz;
	float len = length(to_camera);
	if (len < 0.001) {
		return 0.0;
	}
	vec2 f = to_camera / len;
	vec2 rel = world_pos.xz - cutout_target.xz;
	float along = dot(rel, f);
	float side = abs(rel.x * f.y - rel.y * f.x);
	float toward = smoothstep(target_margin, target_margin + front_softness, along);
	float inside = 1.0 - smoothstep(cutout_front_width - front_softness, cutout_front_width, side);
	return toward * inside;
}

void fragment() {
	float cut = max(hole_amount(), front_amount());
	if (cut > 0.0) {
		// Interleaved gradient noise: a stable per-pixel threshold.
		float threshold = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (cut > threshold) {
			discard;
		}
	}
	if (!FRONT_FACING) {
		ALBEDO = interior_color.rgb;
		ROUGHNESS = 1.0;
	} else {
		vec3 base = albedo.rgb;
		if (use_noise) {
			vec3 blend = abs(world_normal);
			blend /= max(blend.x + blend.y + blend.z, 0.0001);
			vec3 p = world_pos * uv_scale;
			base *= texture(noise_texture, p.zy).rgb * blend.x
				+ texture(noise_texture, p.xz).rgb * blend.y
				+ texture(noise_texture, p.xy).rgb * blend.z;
		}
		base *= mix(1.0, top_darkening, smoothstep(fade_start, top_height, world_pos.y));
		ALBEDO = base;
		ROUGHNESS = roughness_value;
		METALLIC = metallic_value;
		EMISSION = emission_color.rgb * emission_energy;
	}
}
