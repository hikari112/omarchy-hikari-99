#version 440
// Tsukiyo 月夜. The time of day is told with the wallpaper's own processes:
//   day      the sky piece:   12-bit color, noise-dithered, on the art's pixel grid
//   evening  the house piece: four colors, dithered in '/' hatching
//   night    the moon piece:  1-bit, ordered (Bayer) dither
// As the light goes the colors run out, and each change dissolves across the
// screen through the dither itself. At night 月 is the moon: its glow goes
// through the Bayer matrix and breaks into rings, as the light does in the
// moon piece. Nothing here is drawn on top of the picture; everything is the
// picture, processed. Build with build.sh next to this file.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;        // seconds, runs while the screen is awake
    float dusk;        // 0 day .. 1 night: the real sun, or how long you have been away
    float glow;        // breath plus typing
    float tracking;    // wrong password: a tracking error rolling down, 0..1 (0 = none)
    float part;        // unlock, 0..1
    float aspect;      // width / height
    float softness;    // mip level for the living sky
    float cell;        // one pixel of the art, in screen pixels
    float nightCell;   // the moon piece's coarser pixel: twice the day's, so the grids line up
    vec2 res;          // screen size in pixels
    vec2 moonAt;       // centre of 月, 0..1 of the screen
    float moonSize;    // half the kanji's size, in screen heights
    vec4 rings;        // ages of the last four key rings, 0..1 (1 = gone)
    vec4 streak;       // x, y where it starts, age 0..1, 1 if there is one
    vec4 night;        // theme darker_background
    vec4 accent;       // theme accent
    vec4 lilac;        // theme bright_magenta
    vec4 light;        // theme bright_foreground
    vec4 error;        // theme's lock error color
};

layout(binding = 1) uniform sampler2D wall;   // the wallpaper, cropped like the desktop's, mipmapped
layout(binding = 2) uniform sampler2D ink;    // r: 月, g: clock and marks, b: the words on the glass (only to keep the dark round them)

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

// The 8x8 Bayer matrix, 0..1, built up from the 2x2 one
float bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x / 2.0 + a.y * a.y * 0.75);
}
float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

vec3 screenBlend(vec3 base, vec3 add, float amount) {
    return 1.0 - (1.0 - base) * (1.0 - clamp(add * amount, 0.0, 1.0));
}

// A ring of light leaving 月 after a key, `age` 0..1: a thin ripple
float keyRing(float age, float d) {
    if (age >= 1.0) return 0.0;
    float r = 0.12 + age * 0.9;
    return (1.0 - age) * exp(-pow((d - r) / (0.01 + age * 0.014), 2.0));
}

// A streak of light across the dark along the '/', at q
float streakAt(vec2 q) {
    if (streak.w <= 0.0 || streak.z >= 1.0) return 0.0;
    vec2 dir = normalize(vec2(1.0, -0.58));
    vec2 head = vec2(streak.x * aspect, streak.y) + dir * streak.z * 0.9;
    vec2 rel = q - head;
    float along = dot(rel, dir);
    float off = abs(dot(rel, vec2(-dir.y, dir.x)));
    float tail = smoothstep(-0.26, 0.0, along) * step(along, 0.0);
    return tail * exp(-pow(off / 0.0045, 2.0)) * sin(3.14159 * streak.z) * 1.4;
}

void main() {
    vec2 px = qt_TexCoord0 * res;
    vec2 id = floor(px / cell);
    float rows = res.y / cell;

    // Wrong password: the tape loses tracking. Rows in the band slip sideways.
    float band = 0.0;
    if (tracking > 0.0 && tracking < 1.0) {
        float bandY = mix(-0.15, 1.15, tracking);
        band = smoothstep(0.07, 0.0, abs(id.y / rows - bandY));
        float slip = (noise(vec2(id.y * 0.35, time * 9.0)) - 0.5) * 2.0;
        id.x += floor(slip * 7.0 * band + 0.5);
    }

    vec2 uv = (id + 0.5) * cell / res;
    // The night's own, coarser grid
    vec2 nid = floor(px / nightCell);
    vec2 nuv = (nid + 0.5) * nightCell / res;
    vec2 p = vec2(uv.x * aspect, uv.y);
    vec2 centre = vec2(0.5 * aspect, 0.5);
    float t = time;
    float order = bayer8(id);

    // Omarchy's slant, leaning like '/'
    vec2 n = normalize(vec2(1.0, 0.35));
    float across = dot(p - centre, n);

    // The unlock front: behind it the wallpaper, on it a line of light, and
    // just ahead of it the color already coming back
    float ahead = -10.0;
    if (part > 0.0) ahead = part * 1.55 - abs(across) - order * 0.35;

    // ---- the living sky (worked out once per cell)
    vec2 wp = uv * vec2(aspect, 1.0) * 1.5;
    vec2 warp = vec2(fbm(wp + vec2(t * 0.011, t * 0.004)),
                     fbm(wp + vec2(5.2 - t * 0.006, 1.3 + t * 0.009))) - 0.5;
    vec2 tq = (uv - 0.5) * 0.955 + 0.5 + warp * 0.018;
    float period = 26.0;
    float ph0 = fract(t / period);
    float ph1 = fract(t / period + 0.5);
    vec2 wind = vec2(0.0085, -0.0022) * (0.7 + 0.6 * (warp.x + 0.5));
    vec3 sky = mix(textureLod(wall, tq - wind * ph1, softness).rgb,
                   textureLod(wall, tq - wind * ph0, softness).rgb,
                   1.0 - abs(1.0 - 2.0 * ph0));
    float lum = dot(sky, vec3(0.299, 0.587, 0.114));
    float hi = max(sky.r, max(sky.g, sky.b));
    float lo = min(sky.r, min(sky.g, sky.b));
    float sat = (hi - lo) / max(hi, 1e-4);
    float cloud = smoothstep(0.42, 0.16, sat) * smoothstep(0.35, 0.78, lum);
    float clear = smoothstep(0.26, 0.46, sat);

    // ---- 月, the words, and the light that comes off 月
    vec4 inkHere = textureLod(ink, uv, 0.0);
    float kanji = inkHere.r;
    float words = inkHere.g;
    float halo = textureLod(ink, uv, 4.5).r;

    vec2 mc = vec2(moonAt.x * aspect, moonAt.y);
    float dm = length(p - mc);
    float moonlight = exp(-max(0.0, dm - moonSize * 0.6) * 3.2);
    float keyLight = keyRing(rings.x, dm) + keyRing(rings.y, dm) + keyRing(rings.z, dm) + keyRing(rings.w, dm);

    // Now and then, a streak of light across the dark, along the '/'
    float streakLight = streakAt(p);

    // Keep the dark round the words, following their shapes
    vec4 around = textureLod(ink, uv, 3.0);
    float calm = 1.0 - smoothstep(0.015, 0.12, max(around.g, around.b));

    // Which process this cell is in. The switch dissolves through the dither:
    // a cell changes over when the evening or night passes its threshold.
    float nightOn = smoothstep(0.55, 0.72, dusk);
    float eveningOn = smoothstep(0.2, 0.36, dusk);
    float nightOrder = bayer8(nid);
    bool isNight = nightOn > nightOrder && ahead < -0.25;
    bool isEvening = !isNight && eveningOn > hash12(id * 0.73 + 4.1) && ahead < -0.25;

    vec3 col;
    if (isNight) {
        // 1-bit, and everything worked out on the night's own coarse grid,
        // so no edge falls between two cells. Mostly dark, like the moon
        // piece. An eclipse: 月 bright on a dark disc, the light it gives off
        // breaking into rings through the Bayer matrix, dense at the rim, a
        // long sparse tail, black in the corners.
        vec2 np = vec2(nuv.x * aspect, nuv.y);
        float nd = length(np - mc);
        vec4 nInk = textureLod(ink, nuv, 0.0);
        // Hard-edged dark round the words: a soft edge would pass through
        // the Bayer matrix's in-between levels, which are stripes
        vec4 nAround = textureLod(ink, nuv, 2.5);
        float nCalm = 1.0 - step(0.02, max(nAround.g, nAround.b));
        vec3 nSky = textureLod(wall, nuv, softness).rgb;
        float nLum = dot(nSky, vec3(0.299, 0.587, 0.114));
        float nHi = max(nSky.r, max(nSky.g, nSky.b));
        float nSat = (nHi - min(nSky.r, min(nSky.g, nSky.b))) / max(nHi, 1e-4);
        float nCloud = smoothstep(0.42, 0.16, nSat) * smoothstep(0.35, 0.78, nLum);
        float nClear = smoothstep(0.26, 0.46, nSat);
        float rim = moonSize * 1.08;
        float core = 1.0 - smoothstep(rim * 0.94, rim * 1.12, nd);
        float scatter = 0.95 / (1.0 + pow(max(0.0, nd - rim) / 0.12, 2.0)) * (1.0 - smoothstep(0.75, 1.15, nd));
        float ringsHere = keyRing(rings.x, nd) + keyRing(rings.y, nd) + keyRing(rings.z, nd) + keyRing(rings.w, nd);
        float level = (nLum * nCloud * 0.035 + scatter * (0.8 + 0.2 * glow) + ringsHere * 0.3) * (1.0 - core) * nCalm
                    + streakAt(np) * nCalm;
        float starSeed = hash12(nid * 1.37 + 5.0);
        if (starSeed > 0.996 && nd > rim * 2.5) {
            level += (0.6 + 0.4 * sin(t * (0.4 + starSeed * 1.6) + starSeed * 900.0)) * nClear * nCalm;
        }
        col = (level > nightOrder || nInk.r > 0.5 || nInk.g > 0.5) ? light.rgb : night.rgb;
    } else if (isEvening) {
        // Four colors, dithered in '/' hatching, grainy the way the house is
        vec3 p0 = night.rgb;
        vec3 p1 = mix(night.rgb, accent.rgb, 0.55);
        vec3 p2 = mix(accent.rgb, lilac.rgb, 0.6);
        vec3 p3 = mix(lilac.rgb, light.rgb, 0.55);
        // Dark and moody like the house: most of it charcoal and plum, the
        // clouds catching the last light
        float l = pow(smoothstep(0.12, 0.95, lum), 1.4) * (1.0 - 0.55 * dusk);
        l += halo * 0.3 * (0.8 + 0.2 * glow) + keyLight * 0.3 + streakLight;
        float hatch = fract((id.x + id.y * 1.7) / 5.0) * 0.7 + hash12(id) * 0.3;
        float k = clamp(floor(l * 3.0 + hatch), 0.0, 3.0);
        col = k < 0.5 ? p0 : (k < 1.5 ? p1 : (k < 2.5 ? p2 : p3));
        if (max(kanji, words) > 0.5) col = light.rgb;
    } else {
        // 12-bit color with a noise dither: the sky piece itself
        col = sky;
        float dl = length(p - vec2(0.08 * aspect, 0.98));
        col = screenBlend(col, mix(lilac.rgb, light.rgb, 0.45), exp(-dl * dl * 0.9) * glow * (0.25 + 0.55 * cloud));
        float evening = smoothstep(0.0, 0.3, dusk);
        float low = smoothstep(0.2, 1.1, uv.y + (1.0 - uv.x) * 0.35);
        col *= mix(vec3(1.0), vec3(0.8, 0.74, 0.93), evening * (1.0 - low) * 0.8);
        col = screenBlend(col, lilac.rgb, evening * 0.45 * low);
        vec2 m = (uv - vec2(0.5, 0.5)) * vec2(1.5, 1.35);
        col *= 1.0 - 0.22 * exp(-dot(m, m) * 3.2);
        col = screenBlend(col, mix(light.rgb, lilac.rgb, 0.35), halo * (0.5 + 0.3 * glow) + keyLight * 0.35 + streakLight);
        col = mix(col, light.rgb, max(kanji, words));
        // each cell rolls a new dither every couple of seconds, at its own moment
        float roll = floor(t * 0.45 + hash12(id + 91.0) * 7.0);
        vec3 dither = vec3(hash12(id + roll * 13.1), hash12(id + roll * 13.1 + 71.3), hash12(id + roll * 13.1 + 37.9));
        col = floor(clamp(col, 0.0, 1.0) * 15.0 + dither) / 15.0;
    }

    // The tape slipping: the rows in the band shift sideways (above) and
    // the light in them bleeds toward the error color
    if (band > 0.0) {
        col = mix(col, mix(col, error.rgb, 0.5), band * step(0.5, dot(col, vec3(0.333))));
    }

    // Unlock: the wallpaper, exactly as the desktop shows it, behind the front
    if (ahead > 0.06) col = textureLod(wall, qt_TexCoord0, 0.0).rgb;
    else if (ahead > 0.0) col = light.rgb;

    fragColor = vec4(col, 1.0) * qt_Opacity;
}
