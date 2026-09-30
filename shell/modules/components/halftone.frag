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
    
    float cellSize = ubuf.dotMaxSize * 2.0;
    
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
    
    // Project the canvas corners onto the gradient axis to get its full range.
    vec2 corners[4];
    corners[0] = vec2(0.0, 0.0) - center;
    corners[1] = vec2(ubuf.canvasWidth, 0.0) - center;
    corners[2] = vec2(0.0, ubuf.canvasHeight) - center;
    corners[3] = vec2(ubuf.canvasWidth, ubuf.canvasHeight) - center;
    
    float minProj = dot(corners[0], gradientDir);
    float maxProj = minProj;
    for (int i = 1; i < 4; i++) {
        float proj = dot(corners[i], gradientDir);
        minProj = min(minProj, proj);
        maxProj = max(maxProj, proj);
    }
    
    float totalRange = maxProj - minProj;
    
    float activeStart = minProj + ubuf.gradientStart * totalRange;
    float activeEnd = minProj + ubuf.gradientEnd * totalRange;
    float activeRange = max(activeEnd - activeStart, 0.001);
    
    float projection = dot(relativePos, gradientDir);
    
    float dotRadius;
    
    if (projection < activeStart) {
        // Before the start: dots keep growing past the max.
        float distanceBeforeStart = activeStart - projection;
        float growthFactor = distanceBeforeStart / activeRange;
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
    
    fragColor = vec4(finalColor.rgb, finalColor.a * ubuf.qt_Opacity);
}
