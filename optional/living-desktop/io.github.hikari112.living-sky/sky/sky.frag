#version 440
// The desktop, alive: the wallpaper drawn the way it was made, the same sky
// as the Hikari 99 lock screen. The art's pixel grid (800 across), 4 bits per
// channel, and a noise dither each cell re-rolls every couple of seconds at
// its own moment, so the picture sparkles instead of crawling. The clouds
// boil slowly and drift on the wind, a thin haze moves over them, and the
// light in the lilac corner breathes. Build with build.sh next to this file.
//
// Every texture read names its level (textureLod): the coordinates jump at
// each cell of the grid, and a plain texture() would take that jump for a
// huge minification and read a tiny mip along every cell edge.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;        // seconds, runs while the desktop can be seen
    float glow;        // the breathing light in the lilac corner
    float aspect;      // width / height
    float softness;    // mip level for the living sky
    float cell;        // one pixel of the art, in screen pixels
    vec2 res;          // screen size in pixels
    vec4 lilac;        // theme bright_magenta
    vec4 light;        // theme bright_foreground
};

layout(binding = 1) uniform sampler2D wall;   // the wallpaper as the plugin draws it, mipmapped

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 r = mat2(0.8, 0.6, -0.6, 0.8);
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p = r * p * 2.03 + 17.1;
        a *= 0.5;
    }
    return v;
}

vec3 screenBlend(vec3 base, vec3 add, float amount) {
    return 1.0 - (1.0 - base) * (1.0 - clamp(add * amount, 0.0, 1.0));
}

void main() {
    // One pixel of the art: everything is worked out once per cell
    vec2 px = qt_TexCoord0 * res;
    vec2 id = floor(px / cell);
    vec2 uv = (id + 0.5) * cell / res;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time;

    // The clouds boil slowly and drift on the wind, toward the upper right.
    // Two phases half a cycle apart, each faded out as it jumps back.
    vec2 wp = uv * vec2(aspect, 1.0) * 1.5;
    vec2 warp = vec2(fbm(wp + vec2(t * 0.011, t * 0.004)),
                     fbm(wp + vec2(5.2 - t * 0.006, 1.3 + t * 0.009))) - 0.5;
    vec2 tq = (uv - 0.5) * 0.955 + 0.5 + warp * 0.018;
    float period = 26.0;
    float ph0 = fract(t / period);
    float ph1 = fract(t / period + 0.5);
    vec2 wind = vec2(0.0085, -0.0022) * (0.7 + 0.6 * (warp.x + 0.5));
    vec3 col = mix(textureLod(wall, tq - wind * ph1, softness).rgb,
                   textureLod(wall, tq - wind * ph0, softness).rgb,
                   1.0 - abs(1.0 - 2.0 * ph0));

    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float hi = max(col.r, max(col.g, col.b));
    float lo = min(col.r, min(col.g, col.b));
    float sat = (hi - lo) / max(hi, 1e-4);
    float cloud = smoothstep(0.42, 0.16, sat) * smoothstep(0.35, 0.78, lum);

    // A thin haze of its own, drifting faster than the photo
    vec2 hp = uv * vec2(aspect, 1.0) * 2.2 + vec2(-t * 0.016, t * 0.004);
    float wisp = fbm(hp + 0.6 * vec2(fbm(hp * 0.7 + t * 0.010), fbm(hp * 0.7 - t * 0.012)));
    col = mix(col, light.rgb, smoothstep(0.55, 0.88, wisp) * 0.09);

    // The light behind the clouds, from the lilac corner, breathing
    float dl = length(p - vec2(0.08 * aspect, 0.98));
    col = screenBlend(col, mix(lilac.rgb, light.rgb, 0.45), exp(-dl * dl * 0.9) * glow * (0.25 + 0.55 * cloud));

    // 12-bit color with a noise dither, re-rolled per cell every couple of seconds
    float roll = floor(t * 0.45 + hash12(id + 91.0) * 7.0);
    vec3 dither = vec3(hash12(id + roll * 13.1), hash12(id + roll * 13.1 + 71.3), hash12(id + roll * 13.1 + 37.9));
    col = floor(clamp(col, 0.0, 1.0) * 15.0 + dither) / 15.0;

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
