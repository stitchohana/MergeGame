shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 glow_color : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform float core_radius : hint_range(0.0, 0.5) = 0.08;
uniform float outer_radius : hint_range(0.1, 0.75) = 0.42;
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.85;
uniform float glow_opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float source_alpha = source.a;
	float distance_from_center = length(UV - vec2(0.5));
	float radial_glow = 1.0 - smoothstep(core_radius, outer_radius, distance_from_center);
	float halo_alpha = radial_glow * (1.0 - source_alpha * 0.35) * glow_intensity;
	vec3 glow_rgb = glow_color.rgb * halo_alpha * glow_color.a;
	COLOR = vec4((source.rgb + glow_rgb) * glow_opacity, max(source.a, halo_alpha * glow_color.a) * glow_opacity);
}
