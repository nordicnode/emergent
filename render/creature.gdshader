shader_type canvas_item;
render_mode blend_mix;

// One atlas, one material, one blend mode for every creature. The instance's
// custom data carries (frame, hunger urgency, carry code, carry amount); the
// instance colour carries the individual's tint. Batching never breaks on a
// texture switch, and a carried load is drawn by this same pass.

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float frame_count = 8.0;

varying vec4 instance_custom;
varying vec4 instance_color;

void vertex() {
	instance_custom = INSTANCE_CUSTOM;
	instance_color = COLOR;
}

void fragment() {
	float frame = clamp(instance_custom.x, 0.0, frame_count - 1.0);
	vec2 uv = vec2((frame + UV.x) / frame_count, UV.y);
	vec4 tex = texture(atlas, uv);
	vec3 rgb = tex.rgb * instance_color.rgb;
	// Hunger desaturates the same sprite; state is transformation, not an icon.
	float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(lum) * 0.9, clamp(instance_custom.y, 0.0, 1.0) * 0.7);
	float alpha = tex.a * instance_color.a;
	// A carried load: a small blob above the body, coloured by material and
	// sized by amount. One pass, no second node or texture switch.
	float carry = instance_custom.z;
	if (carry > 0.5) {
		vec2 pixel = UV * 16.0;
		vec2 centre = vec2(12.2, 3.2);
		float radius = 1.15 + 0.85 * clamp(instance_custom.w, 0.0, 1.0);
		float d = distance(pixel, centre);
		if (d < radius) {
			rgb = (carry < 1.5) ? vec3(0.95, 0.78, 0.30) : vec3(0.74, 0.64, 0.48);
			alpha = 1.0;
		} else if (d < radius + 0.8) {
			rgb = vec3(0.16, 0.14, 0.12);
			alpha = 1.0;
		}
	}
	COLOR = vec4(rgb, alpha);
}
