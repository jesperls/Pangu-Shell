#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float canvasWidth;
    float canvasHeight;
    float topAlpha;
    vec4 radii;
    vec4 rimColor;
    float bottomAlpha;
    float strokeWidth;
} ubuf;

float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
    vec2 q = (p.x > 0.0) ? ((p.y > 0.0) ? vec2(r.z) : vec2(r.y))
                         : ((p.y > 0.0) ? vec2(r.w) : vec2(r.x));
    float cr = min(q.x, min(b.x, b.y));
    vec2 d = abs(p) - b + cr;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - cr;
}

void main() {
    vec2 size = vec2(max(ubuf.canvasWidth, 1.0), max(ubuf.canvasHeight, 1.0));
    vec2 halfSize = size * 0.5;
    vec2 p = qt_TexCoord0 * size - halfSize;

    float d = sdRoundedBox(p, halfSize, ubuf.radii);
    float outerMask = 1.0 - smoothstep(-0.6, 0.4, d);
    float innerMask = smoothstep(-ubuf.strokeWidth - 0.6, -ubuf.strokeWidth + 0.4, d);
    float ring = clamp(outerMask * innerMask, 0.0, 1.0);

    float diag = clamp(qt_TexCoord0.y * 0.8 + qt_TexCoord0.x * 0.2, 0.0, 1.0);
    float rimAlpha = mix(ubuf.topAlpha, ubuf.bottomAlpha, smoothstep(0.0, 1.0, diag));
    float finalAlpha = ring * rimAlpha * ubuf.rimColor.a * ubuf.qt_Opacity;

    fragColor = vec4(ubuf.rimColor.rgb * finalAlpha, finalAlpha);
}
