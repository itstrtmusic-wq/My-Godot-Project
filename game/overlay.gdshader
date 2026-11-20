shader_type canvas_item;

uniform float strength = 0.0;
uniform bool title_screen = false;
uniform bool damage = false;

void fragment() {
	vec2 uv = UV;
	if (damage) {
		float border = smoothstep(0.24, 0.75, length((uv - 0.5) * vec2(1.25, 1.0)));
		COLOR = vec4(0.72, 0.14, 0.085, strength * border);
	} else if (title_screen) {
		float gradient = smoothstep(0.15, 0.80, uv.x);
		float edge = smoothstep(0.33, 0.54, abs(uv.y - 0.5));
		COLOR = vec4(0.039, 0.071, 0.079, 0.97 - gradient * 0.86 + edge * gradient * 0.23);
	} else {
		COLOR = vec4(0.027, 0.047, 0.052, strength);
	}
}
