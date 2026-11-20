#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float angle;
    float dotMinSize;
    float dotMaxSize;
    float gradientStart;
    float gradientEnd;
    vec4 dotColor;
    vec4 backgroundColor;
    float canvasWidth;
    float canvasHeight;
} ubuf;

#define PI 3.14159265359

void main() {
    vec2 pixelPos = qt_TexCoord0 * vec2(ubuf.canvasWidth, ubuf.canvasHeight);
    
    float angleRad = radians(ubuf.angle);

    float cellSize = max(ubuf.dotMaxSize * 2.0, 1.0);
    
    mat2 rotation = mat2(
        cos(angleRad), -sin(angleRad),
        sin(angleRad), cos(angleRad)
    );
    
    vec2 center = vec2(ubuf.canvasWidth * 0.5, ubuf.canvasHeight * 0.5);
    vec2 relativePos = pixelPos - center;
    
    vec2 rotatedPos = rotation * relativePos;
    
    vec2 gridPos = rotatedPos / cellSize;
    vec2 cellIndex = floor(gridPos + 0.5);
    vec2 cellCenter = cellIndex * cellSize;
    vec2 posInCell = rotatedPos - cellCenter;
    
    float distToCenter = length(posInCell);
    
    // angle=0 -> vertical (top to bottom), angle=90 -> horizontal (left to right)
    vec2 gradientDir = vec2(sin(angleRad), cos(angleRad));
    
    float maxProj = abs(center.x * gradientDir.x) + abs(center.y * gradientDir.y);
    float minProj = -maxProj;
    
    float totalRange = maxProj - minProj;
    
    float activeStart = minProj + ubuf.gradientStart * totalRange;
    float activeEnd = minProj + ubuf.gradientEnd * totalRange;
    float activeRange = max(activeEnd - activeStart, 0.001);
    
    float projection = dot(relativePos, gradientDir);
    
    float dotRadius;
    
    if (projection < activeStart) {
        float distanceBeforeStart = activeStart - projection;
        float growthFactor = min(distanceBeforeStart / activeRange, 1.0);
        dotRadius = ubuf.dotMaxSize * (1.0 + growthFactor);
    } else if (projection > activeEnd) {
        dotRadius = 0.0;
    } else {
        float gradientPos = (projection - activeStart) / activeRange;
        dotRadius = mix(ubuf.dotMaxSize, ubuf.dotMinSize, gradientPos);
    }

    float edgeWidth = length(vec2(dFdx(distToCenter), dFdy(distToCenter))) * 0.5;
    float alpha = 1.0 - smoothstep(dotRadius - edgeWidth, dotRadius + edgeWidth, distToCenter);

    vec4 finalColor = mix(ubuf.backgroundColor, ubuf.dotColor, alpha);

    fragColor = vec4(finalColor.rgb * finalColor.a, finalColor.a) * ubuf.qt_Opacity;
}
