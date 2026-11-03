shader_type canvas_item;
// 受傷／瀕死畫面效果（InjuryOverlay 用）。讀取已畫好的 3D 畫面再加工，UI 在更上層，不受影響。
// 不依賴 RetroScreen：序章（原生解析度）與低解析度管線都能用。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// 低血量強度：HP 30% → 0，5% → 1。
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// 心跳脈動（每拍跳到 1 再衰減）。
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
// 失血：顏色流走、變灰。
uniform float desat : hint_range(0.0, 1.0) = 0.0;
// 左／右眼受損：該側變暗、模糊。
uniform float eye_l : hint_range(0.0, 1.0) = 0.0;
uniform float eye_r : hint_range(0.0, 1.0) = 0.0;
// 頭部重傷：畫面歪斜、晃動。
uniform float wobble : hint_range(0.0, 1.0) = 0.0;
// 雙重影像（HP 很低時）。
uniform float double_vision : hint_range(0.0, 1.0) = 0.0;
// 死亡：畫面從上下被縫起來（1 = 完全縫合）。
uniform float sew : hint_range(0.0, 1.0) = 0.0;
// 一閃而過的小女孩剪影。
uniform float ghost : hint_range(0.0, 1.0) = 0.0;
uniform vec2 ghost_pos = vec2(0.7, 0.55);
uniform float aspect = 1.7778;
// 追逐戰的壓迫感：黑色暗角往內收、顏色褪掉（0–1）。
uniform float dread : hint_range(0.0, 1.0) = 0.0;
// 威脅方向：畫面邊緣朝 threat_dir（螢幕座標，y 向下）的那一側泛紅。
uniform float threat : hint_range(0.0, 1.0) = 0.0;
uniform vec2 threat_dir = vec2(1.0, 0.0);

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);
const vec3 EDGE_RED = vec3(0.16, 0.0, 0.02);
const vec3 GREY_PINK = vec3(1.0, 0.86, 0.86);
const vec3 LID = vec3(0.11, 0.035, 0.04);
const vec3 THREAD = vec3(0.86, 0.80, 0.64);

vec2 rotate_uv(vec2 uv, float a) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	p = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * p;
	return p / vec2(aspect, 1.0) + 0.5;
}

// 小女孩剪影（頭＋裙子），回傳 0–1 遮罩。
float girl(vec2 uv) {
	vec2 p = (uv - ghost_pos) * vec2(aspect, 1.0);
	// 邊緣抖動，讓輪廓不像幾何圖形
	float n = sin(p.y * 180.0 + TIME * 30.0) * 0.0025 + sin(p.y * 67.0) * 0.002;
	float head = 1.0 - smoothstep(0.017, 0.020, length((p - vec2(0.0, -0.078)) * vec2(1.0, 0.9)) + n);
	// 垂下的長髮
	float hair = step(-0.08, p.y) * step(p.y, -0.035) * (1.0 - smoothstep(0.019, 0.022, abs(p.x) + n));
	float t = clamp((p.y + 0.045) / 0.13, 0.0, 1.0);
	float half_w = mix(0.012, 0.042, t * t);
	float body = step(-0.045, p.y) * step(p.y, 0.085) * (1.0 - smoothstep(half_w - 0.003, half_w, abs(p.x) + n));
	// 垂在身側的細手臂
	float arms = step(-0.035, p.y) * step(p.y, 0.035) * (1.0 - smoothstep(0.0025, 0.0045, abs(abs(p.x) - 0.022 - (p.y + 0.035) * 0.15)));
	// 細腿
	float legs = step(0.085, p.y) * step(p.y, 0.12) * (1.0 - smoothstep(0.003, 0.005, abs(abs(p.x) - 0.009)));
	return max(max(head, hair), max(body, max(arms, legs)));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (wobble > 0.0) {
		uv = rotate_uv(uv, sin(TIME * 0.9) * 0.025 * wobble);
		uv += vec2(sin(TIME * 1.7 + uv.y * 6.0), cos(TIME * 1.3 + uv.x * 5.0)) * 0.005 * wobble;
	}
	// 眼睛受損的那一側模糊
	float side_l = smoothstep(0.55, 0.0, SCREEN_UV.x) * eye_l;
	float side_r = smoothstep(0.45, 1.0, SCREEN_UV.x) * eye_r;
	float blur = 2.5 * max(side_l, side_r) + 1.2 * double_vision;
	float ca = 0.0025 * intensity;
	vec3 col;
	col.r = textureLod(screen_tex, uv + vec2(ca, 0.0), blur).r;
	col.g = textureLod(screen_tex, uv, blur).g;
	col.b = textureLod(screen_tex, uv - vec2(ca, 0.0), blur).b;
	if (double_vision > 0.0) {
		vec2 off = vec2(0.014 * sin(TIME * 0.7), 0.004 * cos(TIME * 0.5)) * double_vision;
		col = mix(col, textureLod(screen_tex, uv + off, blur).rgb, 0.45 * double_vision);
	}
	// 失血：顏色流走，偏灰粉
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, lum * GREY_PINK, desat * 0.85);
	// 低血量：亮度色階變少（畫面變「壞」）。只量化亮度並加 Bayer 抖色，避免出現彩色色環。
	if (intensity > 0.0) {
		float levels = mix(40.0, 10.0, intensity);
		ivec2 bp = ivec2(mod(FRAGCOORD.xy, 4.0));
		float th = (BAYER[bp.y * 4 + bp.x] + 0.5) / 16.0 - 0.5;
		float l = max(dot(col, vec3(0.299, 0.587, 0.114)), 1e-4);
		float ql = clamp(floor(l * levels + 0.5 + th * 0.8) / levels, 0.0, 1.0);
		col *= ql / l;
	}
	// 暗紅暗角，隨心跳收縮
	float d = length((SCREEN_UV - 0.5) * vec2(aspect, 1.0));
	float r_out = 1.05 - 0.45 * intensity - 0.07 * pulse * intensity;
	float vig = smoothstep(r_out - 0.55, r_out, d) * step(0.001, intensity);
	col = mix(col, EDGE_RED, vig * (0.4 + 0.55 * intensity));
	// 追逐戰：黑暗從四周收進來，顏色流走
	if (dread > 0.0) {
		float lum2 = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, lum2 * GREY_PINK, dread * 0.35);
		float r_d = 1.1 - 0.5 * dread;
		float vig_d = smoothstep(r_d - 0.6, r_d, d);
		col = mix(col, vec3(0.01, 0.0, 0.005), vig_d * (0.35 + 0.55 * dread));
	}
	// 威脅方向：那一側的邊緣泛起暗紅
	if (threat > 0.0) {
		vec2 p = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
		vec2 dir_n = p / max(length(p), 1e-4);
		float edge = smoothstep(0.3, 0.85, length(p));
		float facing = smoothstep(0.25, 1.0, dot(dir_n, normalize(threat_dir)));
		col = mix(col, vec3(0.42, 0.02, 0.03), edge * facing * threat * 0.85);
	}
	// 失去的眼睛：一側變暗
	col *= 1.0 - 0.85 * max(side_l, side_r);
	// 剪影
	if (ghost > 0.0) {
		col = mix(col, vec3(0.015, 0.0, 0.01), girl(SCREEN_UV) * ghost * 0.85);
	}
	// 死亡：上下眼瞼被縫合
	if (sew > 0.0) {
		// 杏仁形：兩側先合起來，中間最後
		float cx = (SCREEN_UV.x - 0.5) * 2.0;
		float lid = sew * 0.52 + (1.0 - sqrt(max(0.0, 1.0 - cx * cx * 0.9))) * 0.32 * smoothstep(0.0, 0.3, sew);
		float dy = min(SCREEN_UV.y, 1.0 - SCREEN_UV.y);
		float inside = step(dy, lid);
		float near = dy - lid;
		col = mix(col, LID * (0.6 + 0.4 * smoothstep(0.0, 0.15, lid - dy)), inside);
		// 縫線：沿著接縫的斜向線段
		float x = SCREEN_UV.x * aspect;
		float spacing = 0.05;
		float lx = (fract(x / spacing) - 0.5) * spacing;
		float on_seam = step(abs(near), 0.022) * step(sew, 0.999);
		float stitch = 1.0 - smoothstep(0.0018, 0.0034, abs(lx - near * 0.7));
		col = mix(col, THREAD, stitch * on_seam);
		col = mix(col, vec3(0.0), smoothstep(0.85, 1.0, sew));
	}
	COLOR = vec4(col, 1.0);
}
