shader_type spatial;
// 牆後透視：玩家身上 PS1 材質的 next_pass。關掉深度測試畫在所有東西上面，
// 但只在「這個像素前面有別的東西（牆、柱子）擋住玩家」的地方顯示，其他地方丟棄。
// 判斷方式：讀不透明物體的深度貼圖，換算成視空間距離，跟玩家這個像素的距離比較。
// 頂點吸附與 ps1_spatial 相同，剪影不會跟本體錯位。
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// 奶油黃（美術方向色票），半透明
uniform vec4 xray_color : source_color = vec4(0.937, 0.886, 0.69, 1.0);
uniform float base_alpha = 0.28;
uniform float rim_alpha = 0.75;
// 擋在前面的東西至少要比玩家近這麼多（公尺）才算「被擋住」：避免手臂擋到軀幹、武器擋到手時自己亮起來
uniform float margin = 0.6;
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
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_dist = -v.z / v.w;
	float my_dist = -VERTEX.z;
	if (scene_dist > my_dist - margin) {
		discard;
	}
	// 輪廓（邊緣較亮）＋ 2x2 抖動網點，維持 PS1 的顆粒感
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ivec2 p = ivec2(FRAGCOORD.xy) % 2;
	float dither = (p.x == p.y) ? 1.0 : 0.7;
	ALBEDO = xray_color.rgb;
	ALPHA = mix(base_alpha, rim_alpha, rim * rim) * dither;
}
