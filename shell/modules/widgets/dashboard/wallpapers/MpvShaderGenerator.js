.pragma library

function generate(paletteColors) {
    if (!paletteColors || paletteColors.length === 0) {
        return `//!HOOK MAIN
void main() {
    HOOKED_col = HOOKED_tex(HOOKED_pos);
}`;
    }

    let unrolledLogic = "";
    
    for (let i = 0; i < paletteColors.length; i++) {
        let color = paletteColors[i];
        
        let r = (typeof color.r === 'number' ? color.r : 0.0).toFixed(5);
        let g = (typeof color.g === 'number' ? color.g : 0.0).toFixed(5);
        let b = (typeof color.b === 'number' ? color.b : 0.0).toFixed(5);
        
        unrolledLogic += `
    {
        vec3 pColor = vec3(${r}, ${g}, ${b});
        vec3 diff = color - pColor;
        
        vec3 weightedDiff = diff * vec3(0.55, 0.77, 0.34);  // Sqrt of standard luma weights roughly
        float distSq = dot(weightedDiff, weightedDiff); 
        
        if (distSq < minDistSq) {
            minDistSq = distSq;
            closestColor = pColor;
        }

        float weight = exp(-distributionSharpness * distSq);
        accumulatedColor += pColor * weight;
        totalWeight += weight;
    }
`;
    }

    return `//!HOOK MAIN

float noise_random(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 hook() {
    vec4 tex = HOOKED_tex(HOOKED_pos);
    vec3 color = tex.rgb;

    float noise = (noise_random(HOOKED_pos * 100.0 + sin(HOOKED_pos.x)) - 0.5) / 64.0;
    color += noise;

    vec3 accumulatedColor = vec3(0.0);
    float totalWeight = 0.0;
    float minDistSq = 1000.0;
    vec3 closestColor = vec3(0.0);
    
    float distributionSharpness = 40.0; 

    ${unrolledLogic}

    vec3 finalColor;

    if (totalWeight > 0.0001) {
        finalColor = accumulatedColor / totalWeight;
    } else {
        finalColor = closestColor;
    }
    
    return vec4(finalColor, tex.a);
}
`;
}
