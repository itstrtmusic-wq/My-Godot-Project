shader_type spatial;

varying vec3 terrain_position;

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 blend = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), blend.x), blend.y);
}

void vertex() {
	terrain_position = VERTEX;
}

void fragment() {
	vec2 ground = terrain_position.xz;
	float blotch = grain(ground * 0.31);
	float grit = grain(ground * 9.0);
	float track = smoothstep(2.6, 4.2, abs(ground.x + 0.6 * sin(ground.y * 0.16)) + blotch * 1.4);
	float pad = smoothstep(8.0, 12.8, length(ground - vec2(0.0, -13.0)) + blotch * 2.0);
	vec3 gravel = mix(vec3(0.19, 0.16, 0.12), vec3(0.37, 0.32, 0.23), blotch);
	vec3 heath = mix(vec3(0.079, 0.103, 0.086), vec3(0.21, 0.25, 0.155), blotch);
	float ridge = smoothstep(0.3, 5.5, terrain_position.y);
	ALBEDO = mix(mix(gravel, heath, min(track, pad)), vec3(0.21, 0.23, 0.26), ridge) * (0.86 + 0.29 * grit);
	ROUGHNESS = 0.97;
}
