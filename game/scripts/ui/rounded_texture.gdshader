shader_type canvas_item;
uniform vec2 extent = vec2(412.0, 412.0);
uniform float radius = 24.0;
void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	vec2 q = abs(UV * extent - extent * 0.5) - (extent * 0.5 - vec2(radius));
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	pixel.a *= 1.0 - smoothstep(-0.6, 0.6, distance);
	COLOR = pixel;
}
