shader_type canvas_item;
// 低解析度畫面後處理：色階量化（color banding）＋ 4×4 Bayer 抖色（dithering）。
// 只用在 SubViewportContainer 上，UI 不受影響。強度可調，不疊加其他濾鏡。

uniform bool enabled = true;
uniform float color_levels = 24.0;
uniform float dither_strength = 0.6;

const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled) {
		ivec2 p = ivec2(mod(UV / TEXTURE_PIXEL_SIZE, 4.0));
		float threshold = (BAYER[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
		vec3 q = c.rgb * (color_levels - 1.0) + threshold * dither_strength;
		c.rgb = clamp(floor(q + 0.5) / (color_levels - 1.0), 0.0, 1.0);
	}
	COLOR = c;
}
