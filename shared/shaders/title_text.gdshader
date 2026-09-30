shader_type canvas_item;
// Big announcer/winner text: a vertical gold-to-orange gradient down each
// text line (repeating every `line_step` for wrapped text) (the white glyphs take it; the dark outline and drop shadow stay
// dark, since the gradient multiplies), plus the same sweeping shine as
// shine.gdshader. Works in the label's own pixel space.

uniform vec4 top_color : source_color = vec4(1.0, 0.95, 0.55, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.5, 0.08, 1.0);
uniform float line_top = 0.0;
uniform float cap = 40.0;
uniform float line_step = 50.0;
uniform float span = 400.0;
uniform float period = 2.2;
uniform float band = 16.0;
uniform float strength = 0.6;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	// Position inside the current line's capitals, 0 at the top, 1 at the base.
	float y = local.y - line_top;
	float g = clamp((y - floor((y + line_step * 0.25) / line_step) * line_step) / max(cap, 1.0),
			0.0, 1.0);
	// A hard-ish highlight line a third of the way down, like chrome lettering.
	vec3 grad = mix(top_color.rgb, bottom_color.rgb, g);
	grad += vec3(0.25) * (1.0 - smoothstep(0.0, 0.06, abs(g - 0.42)));
	c.rgb *= grad;
	float t = fract(TIME / period);
	float head = mix(-band * 4.0, span * 1.6 + band * 4.0, t);
	float d = abs(local.x + local.y * 0.6 - head);
	float s = (1.0 - smoothstep(0.0, band, d)) * strength;
	c.rgb = mix(c.rgb, vec3(1.0), s * c.a * step(0.5, max(c.r, max(c.g, c.b))));
	COLOR = c;
}
