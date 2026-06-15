shader_type canvas_item;

uniform float strength : hint_range(0.0, 10.0) = 2.5;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec4 col = vec4(0.0);
	vec2 ts = SCREEN_PIXEL_SIZE * strength;

	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-ts.x, -ts.y));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, -ts.y));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(ts.x, -ts.y));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-ts.x, 0.0));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, 0.0));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(ts.x, 0.0));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(-ts.x, ts.y));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(0.0, ts.y));
	col += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(ts.x, ts.y));

	COLOR = col / 9.0;
	COLOR.rgb *= 0.7;
	COLOR.a = 1.0;
}
