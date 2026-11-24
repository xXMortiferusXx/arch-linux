// Dezenter Cursor-Halo: kleiner, schwächer, ruhiger als das gebündelte glow.
// Farbe: heller Blau-Fallback, weil der Noctalia-Akzent sehr dunkel ist.
vec4 cursor(vec2 uv) {
  vec4 c = umbriel_sample(uv);
  float d = distance(uv, umbriel_pointer) * 2.0;
  float breath = 0.9 + 0.1 * sin(umbriel_time * 2.0);
  vec4 tint = umbriel_palette_count > 0 ? umbriel_palette_at(0.0) : vec4(0.48, 0.64, 1.0, 1.0);
  float halo = exp(-d * d * 10.0) * 0.22 * breath;
  return c * (1.0 - halo) + tint * halo;
}
