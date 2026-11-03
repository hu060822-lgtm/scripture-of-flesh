shader_type spatial;
// 受擊閃白的疊加層（GeometryInstance3D.material_overlay）。頂點吸附與 ps1_spatial 相同，
// 疊在原本的網格上不會錯位；不打光、加法混合，把網格整個打亮成骨瓷白。
// 不用 instance uniform：相容（OpenGL）渲染器不支援。
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform vec4 flash_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
uniform float strength = 1.0;
uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform bool jitter_enabled = true;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (jitter_enabled && snap_resolution.x > 0.0) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = round(ndc.xy * snap_resolution * 0.5) / (snap_resolution * 0.5);
		clip = vec4(ndc * clip.w, clip.w);
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = flash_color.rgb * strength;
}
