#ifdef GL_ES
precision highp float;
#endif

#if __VERSION__ >= 140
in vec4 Tint;
in vec2 UV;
in vec2 StepUV;
out vec4 fragColor;
#else
varying vec4 Tint;
varying vec2 UV;
varying vec2 StepUV;
#define fragColor gl_FragColor
#define texture texture2D
#endif

uniform sampler2D Texture0;

void main(void) {
    // Inner alpha boundary only: neither the coloured interior nor an opaque
    // fill survives. Sampling the live silhouette preserves costume shapes.
    float center = texture(Texture0, UV).a;
    float inside = min(texture(Texture0, UV + vec2(StepUV.x, 0.0)).a,
                       texture(Texture0, UV - vec2(StepUV.x, 0.0)).a);
    inside = min(inside, texture(Texture0, UV + vec2(0.0, StepUV.y)).a);
    inside = min(inside, texture(Texture0, UV - vec2(0.0, StepUV.y)).a);
    float edge = max(0.0, center - inside);
    // The game's current blend mode may keep RGB even at alpha zero. Never
    // submit colour outside the outline (this quad spans the full viewport).
    if (edge * Tint.a <= 0.0) discard;
    fragColor = vec4(Tint.rgb, edge * Tint.a);
}
