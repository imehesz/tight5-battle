shader_type canvas_item;
// A bright diagonal band that sweeps across the node every `period` seconds,
// only over its opaque pixels (text, logo, icons, card art). Works in the
// node's own pixel space, so it needs the node's width in `span`.

uniform float span = 200.0;
uniform float period = 2.6;
uniform float band = 18.0;
uniform float strength = 0.75;
uniform float offset = 0.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float t = fract(TIME / period + offset);
	// The band travels from well left of the node to well right of it, then
	// rests off-screen for the rest of the period.
	float head = mix(-band * 4.0, span * 1.6 + band * 4.0, t);
	float d = abs(local.x + local.y * 0.6 - head);
	float s = (1.0 - smoothstep(0.0, band, d)) * strength;
	c.rgb = mix(c.rgb, vec3(1.0), s * c.a);
	COLOR = c;
}
