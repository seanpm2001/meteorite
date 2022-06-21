layout(location = 0) in vec2 v_TexCoord;
layout(location = 1) in float v_Diffuse;

layout(location = 0) out vec4 color;

layout(set = 0, binding = 0) uniform texture2D u_Texture;
layout(set = 0, binding = 1) uniform sampler u_Sampler;

#ifdef TONEMAP
    #include lib/tonemap
#endif

void main() {
    vec4 c = texture(sampler2D(u_Texture, u_Sampler), v_TexCoord);
    if (c.a <= 0.75) discard;

    c *= vec4(v_Diffuse, v_Diffuse, v_Diffuse, 1.0);

    color = c;
}