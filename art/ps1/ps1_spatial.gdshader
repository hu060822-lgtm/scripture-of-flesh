shader_type spatial;
// PS1 風格材質：頂點吸附（有限的抖動）、點取樣低解析度貼圖、無鏡面反射、可選自發光（弱點與器官辨識）。
render_mode diffuse_lambert, specular_disabled, cull_back;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// 頂點吸附的格點解析度（越小抖動越明顯）；0 = 關閉。
uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform bool jitter_enabled = true;

void vertex() {
	// 一旦寫入 POSITION，引擎就不再自動計算位置，所以關閉抖動時也要寫入。
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (jitter_enabled && snap_resolution.x > 0.0) {
		vec3 ndc = clip.xyz / clip.w;
		ndc.xy = round(ndc.xy * snap_resolution * 0.5) / (snap_resolution * 0.5);
		clip = vec4(ndc * clip.w, clip.w);
	}
	POSITION = clip;
	UV = UV * uv_scale;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * albedo.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = emission.rgb * emission_energy;
}
