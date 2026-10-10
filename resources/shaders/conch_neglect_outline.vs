#ifdef GL_ES
precision highp float;
#endif

#if __VERSION__ >= 140
in vec3 Position;
in vec4 Color;
in vec2 TexCoord;
in vec2 TexelStep;
out vec4 Tint;
out vec2 UV;
out vec2 StepUV;
#else
attribute vec3 Position;
attribute vec4 Color;
attribute vec2 TexCoord;
attribute vec2 TexelStep;
varying vec4 Tint;
varying vec2 UV;
varying vec2 StepUV;
#endif

uniform mat4 Transform;

void main(void) {
    gl_Position = Transform * vec4(Position, 1.0);
    Tint = Color;
    UV = TexCoord;
    StepUV = TexelStep;
}
