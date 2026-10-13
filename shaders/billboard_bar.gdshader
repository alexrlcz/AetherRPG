shader_type spatial;
// Camera-facing horizontal bar (e.g. health). Drawn on top of geometry.
// `ratio` is per-instance so many bars can share one material.
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

instance uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.85, 0.15, 0.15, 1.0);
uniform vec4 back_color : source_color = vec4(0.08, 0.06, 0.06, 0.85);
uniform float border = 0.08;

void vertex() {
	// Billboard: keep the node's position, use the camera's orientation.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	// Border is `border` of the bar height. Convert to UV.x units using the
	// on-screen aspect (UV change per pixel horizontally vs vertically).
	float aspect = length(dFdx(UV)) / max(length(dFdy(UV)), 1e-5);
	float bx = border * aspect;
	bool inside = UV.y > border && UV.y < 1.0 - border && UV.x > bx && UV.x < 1.0 - bx;
	float fill_x = mix(bx, 1.0 - bx, ratio);
	vec4 c = (inside && UV.x <= fill_x) ? fill_color : back_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
