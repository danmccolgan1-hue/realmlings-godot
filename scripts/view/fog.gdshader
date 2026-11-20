// Fog of war (web: game.js renderFog): the mask is white where the land is explored (plus a band of sea along its
// coasts); everything else is dark blue with soft clouds drawn on it.
shader_type canvas_item;

uniform vec2 origin;
uniform float ms;
const vec3 FOG = vec3(0.184, 0.231, 0.333);

varying vec2 wpos;

void vertex() {
	wpos = origin + VERTEX / ms;
}

float hash(vec2 g) {
	float h = sin(g.x * 12.9898 + g.y * 78.233) * 43758.5453;
	return h - floor(h);
}

// a cloud: five puffs merged into one shape
bool in_cloud(vec2 p, vec2 c, float r, float dy) {
	vec3 puffs[5] = vec3[](vec3(0.0, 0.0, 1.0), vec3(-1.1, 0.35, 0.72), vec3(1.1, 0.3, 0.78), vec3(-0.45, -0.55, 0.75), vec3(0.55, -0.5, 0.82));
	for (int i = 0; i < 5; i++) {
		if (distance(p, c + vec2(puffs[i].x * r, puffs[i].y * r + dy)) < puffs[i].z * r) return true;
	}
	return false;
}

void fragment() {
	// the mask is coarse: average a few taps around the spot so its edge is soft, not stepped
	float m = 0.0;
	for (int i = -2; i <= 2; i++) for (int j = -2; j <= 2; j++) {
		m += texture(TEXTURE, UV + vec2(float(i), float(j)) * TEXTURE_PIXEL_SIZE * 0.9).r;
	}
	m /= 25.0;
	vec3 col = FOG;
	float step_ = 360.0;
	vec2 cell = floor(wpos / step_);
	for (int i = -1; i <= 1; i++) for (int j = -1; j <= 1; j++) {
		vec2 g = (cell + vec2(float(i), float(j))) * step_;
		float f = hash(g);
		float f2 = mod(f * 7.31, 1.0);
		float f3 = mod(f * 13.7, 1.0);
		vec2 c = g + vec2(f, f2) * step_ * 0.6;
		float r = 60.0 + f3 * 40.0;
		if (in_cloud(wpos, c, r, r * 0.35)) col = mix(col, vec3(12.0, 18.0, 36.0) / 255.0, 0.22);
		if (in_cloud(wpos, c, r, 0.0)) col = mix(col, vec3(196.0, 210.0, 232.0) / 255.0, 0.20);
		if (distance(wpos, c + vec2(-r * 0.35, -r * 0.45)) < r * 0.55) col = mix(col, vec3(236.0, 242.0, 252.0) / 255.0, 0.14);
	}
	COLOR = vec4(col, 1.0 - smoothstep(0.15, 0.85, m));
}
