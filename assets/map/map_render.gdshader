shader_type canvas_item;
// Map compositor. Runs on a ColorRect sized to the bitmap canvas.
//
// Inputs:
//   province_tex  — RGB8 encodes cell id (R|G<<8|B<<16). A=255 always.
//   terrain_tex   — RGB8 per-pixel terrain tint (pre-shaded at bake).
//   shading_tex   — R8 hillshade (0..1 darkness factor).
//   palette_tex   — N×1 RGBA, indexed by cell id. RGB = political colour,
//                   A = kingdom index (0 unclaimed, 1..N kingdoms, 255 sea).
//   hover_id, select_id — cell ids currently under cursor / selected.
//   zoom — current view zoom (1 = fit, up to ~10). Controls border width
//          and palette blend strength so close-in zooms show terrain,
//          far-out zooms show political colour.
//   bitmap_size — texel size in pixels for border sampling.

uniform sampler2D province_tex : filter_nearest;
uniform sampler2D terrain_tex  : filter_linear_mipmap;
uniform sampler2D shading_tex  : filter_linear_mipmap;
uniform sampler2D palette_tex  : filter_nearest;

uniform int hover_id  = 0;
uniform int select_id = 0;
uniform float zoom    = 1.0;
uniform vec2 bitmap_size = vec2(2048.0, 1024.0);
uniform float palette_count = 2048.0;

// Blend terrain↔political as the user zooms in.
//   zoom 1..2  → political colour dominant
//   zoom 4..10 → terrain dominant
uniform float political_zoom_start = 0.9;
uniform float political_zoom_end   = 3.2;

int cell_id_from_rgb(vec3 c) {
	int r = int(c.r * 255.0 + 0.5);
	int g = int(c.g * 255.0 + 0.5);
	int b = int(c.b * 255.0 + 0.5);
	return r | (g << 8) | (b << 16);
}

vec4 palette_lookup(int id) {
	float u = (float(id) + 0.5) / palette_count;
	return texture(palette_tex, vec2(u, 0.5));
}

void fragment() {
	vec2 uv = UV;

	vec3 prov_rgb = texture(province_tex, uv).rgb;
	int id = cell_id_from_rgb(prov_rgb);

	vec4 pal = palette_lookup(id);
	int kingdom = int(pal.a * 255.0 + 0.5);

	vec3 terrain = texture(terrain_tex, uv).rgb;
	float shade  = texture(shading_tex, uv).r;

	// Political vs terrain blend driven by zoom.
	float pol_mix = 1.0 - smoothstep(political_zoom_start, political_zoom_end, zoom);
	vec3 political = pal.rgb;
	// Sea cells (kingdom=255) always show terrain (water) — never political.
	if (kingdom == 255) {
		pol_mix = 0.0;
	}
	// Unclaimed land (kingdom=0) fades political to neutral parchment.
	if (kingdom == 0 && id > 0) {
		political = mix(terrain, vec3(0.78, 0.72, 0.54), 0.25);
	}

	vec3 base = mix(terrain, political, pol_mix * 0.75);

	// Hillshade.
	// Shade channel is 0..1. Remap so shade < 0.5 darkens and > 0.5
	// lightens, with a soft shoulder to avoid crushing.
	float shade_bias = (shade - 0.5) * 0.55;
	base *= (1.0 + shade_bias);

	// Border detection: 4-neighbour sample. Any neighbour with a
	// different cell id is a cell border; different kingdom is a
	// kingdom border (thicker, darker).
	vec2 texel = 1.0 / bitmap_size;
	int id_l = cell_id_from_rgb(texture(province_tex, uv + vec2(-texel.x, 0.0)).rgb);
	int id_r = cell_id_from_rgb(texture(province_tex, uv + vec2( texel.x, 0.0)).rgb);
	int id_u = cell_id_from_rgb(texture(province_tex, uv + vec2(0.0, -texel.y)).rgb);
	int id_d = cell_id_from_rgb(texture(province_tex, uv + vec2(0.0,  texel.y)).rgb);
	bool cell_edge = (id_l != id) || (id_r != id) || (id_u != id) || (id_d != id);

	int k_l = int(palette_lookup(id_l).a * 255.0 + 0.5);
	int k_r = int(palette_lookup(id_r).a * 255.0 + 0.5);
	int k_u = int(palette_lookup(id_u).a * 255.0 + 0.5);
	int k_d = int(palette_lookup(id_d).a * 255.0 + 0.5);
	bool kingdom_edge = (k_l != kingdom) || (k_r != kingdom) || (k_u != kingdom) || (k_d != kingdom);

	// Cell borders fade in as we zoom in, so world-view isn't a mesh
	// of ink. Kingdom borders always visible.
	float cell_border_weight = smoothstep(1.4, 3.0, zoom);
	if (cell_edge && !kingdom_edge) {
		base *= mix(1.0, 0.78, cell_border_weight);
	}
	if (kingdom_edge && kingdom != 255 && k_l != 255 && k_r != 255 && k_u != 255 && k_d != 255) {
		// Land-land kingdom border: dark ink.
		base *= 0.55;
	} else if (kingdom_edge && kingdom != 255) {
		// Coastline: subtle darkening seaward, so shore reads.
		base *= 0.78;
	}

	// Hover / select highlight.
	if (id > 0 && id == hover_id) {
		base += vec3(0.08, 0.08, 0.05);
	}
	if (id > 0 && id == select_id) {
		base = mix(base, vec3(1.0, 0.92, 0.55), 0.35);
	}

	COLOR = vec4(base, 1.0);
}
