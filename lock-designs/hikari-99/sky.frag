#version 440
// Hikari 99: Hikari's living sky, drawn the way the wallpaper itself was
// made. The art's pixel grid (800 across), 4 bits per channel, and a noise
// dither between neighbouring levels that each cell re-rolls every couple of
// seconds, so the picture sparkles instead of crawling. 光, its glow, the
// pencil marks, the stars and every light are part of that picture and go
// through the same process. Build with build.sh next to this file.
//
// Every texture read names its level (textureLod): the coordinates jump at
// each cell of the grid, and a plain texture() would take that jump for a
// huge minification and read a tiny mip along every cell edge.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;        // seconds, runs while the screen is awake
    float dusk;        // 0 day .. 1 night, how long you have been away
    float glow;        // the light behind the clouds, breath plus typing
    float shadow;      // wrong password: a cloud shadow crossing, 0..1 (0 = none)
    float part;        // unlock: the clouds part, 0..1
    float settle;      // unlock: back to the exact wallpaper, 0..1
    float bloom;       // unlock: 光 lights up
    float errorOn;     // the marks after a wrong password
    float aspect;      // width / height
    float softness;    // mip level for the living sky
    float cell;        // one pixel of the art, in screen pixels
    vec2 res;          // screen size in pixels
    vec4 pulseA;       // key light: x, y, age 0..1, strength
    vec4 pulseB;
    vec4 pulseC;
    vec4 pulseD;
    vec4 night;        // theme darker_background
    vec4 accent;       // theme accent
    vec4 lilac;        // theme bright_magenta
    vec4 light;        // theme bright_foreground
    vec4 error;        // the lock's error color
};

layout(binding = 1) uniform sampler2D wall;   // the wallpaper, cropped like the desktop's, mipmapped
layout(binding = 2) uniform sampler2D ink;    // r: 光, g: the pencil marks and their line; mipmapped

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

float keyLight(vec4 k, vec2 p) {
    if (k.w <= 0.0 || k.z >= 1.0) return 0.0;
    vec2 c = vec2(k.x * aspect, k.y);
    float r = 0.08 + 0.34 * k.z;
    float d = length(p - c);
    return k.w * smoothstep(0.0, 0.12, k.z) * pow(1.0 - k.z, 1.7) * exp(-(d * d) / (r * r));
}

void main() {
    // One pixel of the art: everything below is worked out once per cell
    vec2 px = qt_TexCoord0 * res;
    vec2 id = floor(px / cell);
    vec2 uv = (id + 0.5) * cell / res;
    vec2 p = vec2(uv.x * aspect, uv.y);
    vec2 centre = vec2(0.5 * aspect, 0.5);
    float live = 1.0 - settle;
    float t = time;

    // Omarchy's slant, leaning like '/'
    vec2 n = normalize(vec2(1.0, 0.35));
    float across = dot(p - centre, n);

    // Unlock: the clouds on each side slide away from the slant
    float open = part * live;
    float gap = open * 0.34;
    float moved = sign(across) * min(abs(across), gap * exp(-abs(across) * 1.4));
    vec2 q = vec2((p.x - n.x * moved) / aspect, p.y - n.y * moved);
    float smear = open * 3.2 * exp(-abs(across) / (gap + 0.04));

    // The clouds boil slowly and drift on the wind
    vec2 wp = q * vec2(aspect, 1.0) * 1.5;
    vec2 warp = vec2(fbm(wp + vec2(t * 0.011, t * 0.004)),
                     fbm(wp + vec2(5.2 - t * 0.006, 1.3 + t * 0.009))) - 0.5;
    vec2 tq = (q - 0.5) * (1.0 - 0.045 * live) + 0.5 + warp * 0.018 * live;
    float period = 26.0;
    float ph0 = fract(t / period);
    float ph1 = fract(t / period + 0.5);
    vec2 wind = vec2(0.0085, -0.0022) * (0.7 + 0.6 * (warp.x + 0.5)) * live;
    vec3 col = mix(textureLod(wall, tq - wind * ph1, softness + smear).rgb,
                   textureLod(wall, tq - wind * ph0, softness + smear).rgb,
                   1.0 - abs(1.0 - 2.0 * ph0));

    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float hi = max(col.r, max(col.g, col.b));
    float lo = min(col.r, min(col.g, col.b));
    float sat = (hi - lo) / max(hi, 1e-4);
    float cloud = smoothstep(0.42, 0.16, sat) * smoothstep(0.35, 0.78, lum);
    float clear = smoothstep(0.26, 0.46, sat);

    // A thin haze of its own, drifting faster than the photo
    vec2 hp = uv * vec2(aspect, 1.0) * 2.2 + vec2(-t * 0.016, t * 0.004);
    float wisp = fbm(hp + 0.6 * vec2(fbm(hp * 0.7 + t * 0.010), fbm(hp * 0.7 - t * 0.012)));
    wisp = smoothstep(0.55, 0.88, wisp) * 0.09 * live;
    col = mix(col, light.rgb, wisp);

    // The light behind the clouds, from the lilac corner, breathing
    float dl = length(p - vec2(0.08 * aspect, 0.98));
    col = screenBlend(col, mix(lilac.rgb, light.rgb, 0.45), exp(-dl * dl * 0.9) * glow * (0.25 + 0.55 * cloud) * live);

    // Each key pushes a little light through
    float keys = keyLight(pulseA, p) + keyLight(pulseB, p) + keyLight(pulseC, p) + keyLight(pulseD, p);
    col = screenBlend(col, light.rgb, min(keys, 1.2) * (0.10 + 0.35 * cloud) * live);

    // Away: evening, then night
    float dk = dusk * live;
    float low = smoothstep(0.2, 1.1, uv.y + (1.0 - uv.x) * 0.35);
    float evening = smoothstep(0.0, 0.35, dk);
    float sunset = evening * (1.0 - smoothstep(0.4, 0.8, dk));
    col *= mix(vec3(1.0), vec3(0.78, 0.72, 0.92), evening * (1.0 - low) * 0.85);
    col = screenBlend(col, lilac.rgb, sunset * 0.5 * low);
    vec3 nightSky = night.rgb * 1.5 + accent.rgb * (0.10 + 0.22 * cloud) * lum + col * 0.10;
    col = mix(col, nightSky, smoothstep(0.2, 1.0, dk) * 0.92);

    // Wrong password: a cloud's shadow passes over, across the slant
    if (shadow > 0.0 && shadow < 1.0) {
        float front = mix(-1.5, 1.5, shadow);
        float edge = (fbm(p * 2.6 + t * 0.05) - 0.5) * 0.5;
        float band = smoothstep(0.42, 0.0, abs(across + edge - front));
        col *= 1.0 - 0.42 * band;
        col = mix(col, col * vec3(0.82, 0.86, 1.06), band * 0.6);
    }

    // Unlock light floods the gap, then everything else
    float spread = 0.03 + open * 0.55;
    float flood = open * (exp(-(across * across) / (spread * spread)) * 0.95 + open * 0.30);
    col = mix(col, mix(light.rgb, lilac.rgb, 0.22), clamp(flood, 0.0, 0.9));

    // A little shade behind the words in the middle
    vec2 m = (uv - vec2(0.5, 0.5)) * vec2(1.5, 1.35);
    col *= 1.0 - 0.24 * exp(-dot(m, m) * 3.2) * live * (1.0 - dk) * (1.0 - open);

    // 光 and the marks, drawn into the picture. Round 光 a deep periwinkle
    // glow so the light reads on a white cloud; the unlock turns it to light.
    vec4 inkHere = textureLod(ink, uv, 0.0);
    float halo = textureLod(ink, uv, 4.5).r;
    vec3 deep = mix(accent.rgb, night.rgb, 0.55);
    col = mix(col, deep, clamp(halo * 1.4, 0.0, 0.6) * (1.0 - bloom) * live);
    col = screenBlend(col, mix(light.rgb, lilac.rgb, 0.4), halo * 1.6 * bloom);
    col = mix(col, light.rgb, inkHere.r);
    col = mix(col, mix(light.rgb, error.rgb, errorOn), inkHere.g);

    // 12-bit color with a noise dither. The noise is fixed to each cell and
    // each cell rolls a new one every couple of seconds, at its own moment.
    float roll = floor(t * 0.45 + hash12(id + 91.0) * 7.0);
    vec3 dither = vec3(hash12(id + roll * 13.1), hash12(id + roll * 13.1 + 71.3), hash12(id + roll * 13.1 + 37.9));
    col = floor(clamp(col, 0.0, 1.0) * 15.0 + dither) / 15.0;

    // Stars: single cells of light in the gaps between the clouds
    float starsOn = smoothstep(0.55, 0.95, dk);
    float starSeed = hash12(id * 1.37 + 5.0);
    if (starsOn > 0.0 && starSeed > 0.9975) {
        float twinkle = 0.55 + 0.45 * sin(t * (0.4 + starSeed * 1.6) + starSeed * 900.0);
        if (starsOn * twinkle * clear * (1.0 - wisp * 6.0) > hash12(id + 17.0) * 0.6) col = light.rgb;
    }

    // Handing back: cell by cell, in no order, the exact wallpaper
    if (settle > 0.0 && settle >= hash12(id * 0.91 + 3.7)) col = textureLod(wall, qt_TexCoord0, 0.0).rgb;

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
