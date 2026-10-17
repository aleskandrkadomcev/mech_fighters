// Pixel Dreamer — Hologram with Scanlines (Godot 4 · spatial · Forward+/Mobile/Compatibility)
// godotshaders.com/shader/hologram-with-scanlines/ — автор pixeldreamerstudio — MIT License · https://pixeldreamerstudio.itch.io/
// Fresnel rim + moving scanlines + flicker + glitch slices. Works on any mesh.
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 holo_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.6;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.5;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.15;
uniform float line_density = 60.0; // scanlines per world unit
uniform float line_speed = 1.2;
uniform float line_strength : hint_range(0.0, 1.0) = 0.5;
uniform float flicker : hint_range(0.0, 1.0) = 0.15;
uniform float glitch : hint_range(0.0, 0.2) = 0.03; // sideways jump of random slices

varying float world_y;

float h1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float slice = floor(wp.y * 12.0 + floor(TIME * 8.0) * 3.7);
	float g = step(0.93, h1(slice + floor(TIME * 8.0))) * (h1(slice * 3.1) - 0.5) * 2.0;
	VERTEX.x += g * glitch;
	world_y = wp.y;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float lines = 0.5 + 0.5 * sin((world_y * line_density - TIME * line_speed * 10.0));
	lines = mix(1.0, lines, line_strength);
	float band = smoothstep(0.0, 0.08, abs(fract(world_y * 0.6 - TIME * 0.35) - 0.5)) ;
	band = mix(1.6, 1.0, band);
	float fl = 1.0 - flicker * step(0.92, h1(floor(TIME * 20.0)));
	float a = (base_alpha + fres) * lines * band * fl;
	ALBEDO = holo_color.rgb * a * energy;
}
