#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D paletteTexture;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float paletteSize;
    float texWidth;
    float texHeight;
} ubuf;

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    vec3 color = tex.rgb;

    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;
    
    int size = int(ubuf.paletteSize);
    float distributionSharpness = 20.0;

    for (int i = 0; i < 128; i++) {
        if (i >= size) break;

        float u = (float(i) + 0.5) / ubuf.paletteSize;
        vec3 pColor = texture(paletteTexture, vec2(u, 0.5)).rgb;

        vec3 weightedDiff = (color - pColor) * vec3(0.55, 0.77, 0.34);
        float distSq = dot(weightedDiff, weightedDiff);
        float weight = exp(-distributionSharpness * distSq);

        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }

    vec3 finalColor = accumulatedColor / (totalWeight + 0.00001);
    fragColor = vec4(finalColor * tex.a, tex.a) * ubuf.qt_Opacity;
}
