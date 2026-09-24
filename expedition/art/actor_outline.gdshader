shader_type canvas_item;
uniform vec4 rim_color : source_color = vec4(0.91,0.87,0.72,0.65);
varying vec4 vertex_tint;
void vertex() {
	vertex_tint = COLOR;
}
void fragment() {
	vec4 modulation = vertex_tint;
	vec4 source = texture(TEXTURE, UV);
	vec2 step_uv = max(fwidth(UV), TEXTURE_PIXEL_SIZE);
	float edge = max(max(texture(TEXTURE,UV+vec2(step_uv.x,0.0)).a,texture(TEXTURE,UV-vec2(step_uv.x,0.0)).a),
		max(texture(TEXTURE,UV+vec2(0.0,step_uv.y)).a,texture(TEXTURE,UV-vec2(0.0,step_uv.y)).a));
	vec4 rim = vec4(rim_color.rgb, edge*rim_color.a);
	COLOR = vec4(mix(rim.rgb,source.rgb,source.a),max(source.a,rim.a))*modulation;
}
