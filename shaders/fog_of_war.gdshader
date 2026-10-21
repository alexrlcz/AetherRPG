shader_type spatial;
// Fog of war as one full-screen pass (FogOfWar puts it on a quad in front
// of the camera). Every pixel's world position comes from the depth buffer
// and is turned back into a cell point (the level's warp inverted by
// fixed-point iteration, as DungeonLayout.to_cell() does), which looks up
// `fog_mask` (cell space: R = explored 0..1, G = in line of sight). Light =
// line of sight times a smooth falloff with the distance to `viewer` (the
// player's cell point): full up to `sight_radius`, gone at `sight_fade`. The pixel is multiplied by a
// blend of black (unexplored), `explored_tint` (seen before, unlit) and 1
// (lit).
// Drawn first among transparent things (render_priority), so damage
// numbers, health bars and silhouettes stay on top.
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D fog_mask : filter_linear, repeat_disable;
// Cell point at the mask's corner, and the mask's size in cells.
uniform vec2 mask_origin;
uniform vec2 mask_size = vec2(1.0);
// DungeonLayout: world = (warp(cell) - layout_origin) * cell_size.
uniform vec2 layout_origin;
uniform float cell_size = 2.0;
// Warp waves (DungeonLayout.warp_waves()): the first `waves_per_axis` move
// x, the next as many move y. xy = direction, z = wave number, w = phase.
uniform int waves_per_axis = 0;
uniform vec4 waves[8];
uniform float amplitudes[8];
uniform vec3 explored_tint : source_color = vec3(0.34, 0.36, 0.48);
// The player's cell point and the light's falloff (cells).
uniform vec2 viewer;
uniform float sight_radius = 3.5;
uniform float sight_fade = 5.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec2 warp(vec2 cell) {
	vec2 offset = vec2(0.0);
	for (int i = 0; i < waves_per_axis * 2; i++) {
		float s = amplitudes[i] * sin(dot(waves[i].xy, cell) * waves[i].z + waves[i].w);
		if (i < waves_per_axis) {
			offset.x += s;
		} else {
			offset.y += s;
		}
	}
	return cell + offset;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	vec2 target = world.xz / cell_size + layout_origin;
	vec2 cell = target;
	for (int i = 0; i < 8; i++) {
		cell += target - warp(cell);
	}
	vec2 uv = (cell - mask_origin) / mask_size;
	vec2 state = texture(fog_mask, uv).rg;
	// Nothing drawn here (reverse Z: far = 0) or off the mask: black.
	if (depth <= 0.0 || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		state = vec2(0.0);
	}
	float falloff = 1.0 - smoothstep(sight_radius, sight_fade, distance(cell, viewer));
	float light = state.g * falloff;
	vec3 explored = explored_tint * max(state.r, light);
	ALBEDO = mix(explored, vec3(1.0), light);
}
