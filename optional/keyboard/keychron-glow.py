#!/usr/bin/env python3
"""Keychron Q6 Max lighting in the colors of the Omarchy theme.

The board is a window onto the Hikari 99 sky: its colors come from the
wallpaper itself (baked in below; the board keeps this sky whatever the
theme), lilac in the lower left, periwinkle across, deeper blue toward the
upper right. Soft clouds drift over it toward the upper right, the
way the desktop's do, slowly changing shape; under a cloud the keys go white,
the brightest they get, and in clear sky they sink into deep color, which on
an LED is dimmer. The lilac corner breathes, on the wall clock, in time with
the desktop's. Every key keeps its hue; clouds and the breath move only its
saturation, and the board runs at full brightness, where the firmware has 256
steps per channel instead of a few dozen: the motion is smooth instead of
ticking. The service owns the brightness (the knob is put back).

SCENE = "gradient" brings back the earlier look: the theme's gradient along
the slant with drifting light, and a breathing board, which does follow the
theme: when it changes, the board breathes out, the new gradient rolls in on
a slant, and it blooms back.

The Hikari lock screen plays along over a local socket: while locked the
board settles into the screen's slow breath and deepens with its evening sky,
each key sends light across the board, a wrong password is a shadow passing
over, and the unlock spreads light out from the slant with the screen. It is
told what happened, never which key.

Runs as the keychron-glow user service. --once sets the colors and exits.
Only the Keychron Q6 Max, ANSI with knob, on its cable: see BOARD_ID.
"""

import colorsys
import glob
import math
import os
import select
import random
import signal
import socket
import subprocess
import sys
import time
import tomllib

COLORS = os.path.expanduser("~/.local/state/omarchy/current/theme/colors.toml")
PEAK_FILE = os.path.expanduser("~/.local/state/keychron-glow/peak")

# Q6 Max ANSI knob: LED index -> position, 0-224 across and 0-64 down.
# Indices follow the keyboard's own firmware (v1.1.1), which numbers the
# right-hand column at the end of each row, unlike the published source.
LED_X = (0,13,24,34,45,57,68,78,89,102,112,123,133,159,169,180,193,203,214,224,0,10,21,31,42,52,63,73,83,94,104,115,125,141,159,169,180,193,203,214,224,3,16,26,36,47,57,68,78,89,99,109,120,130,143,159,169,180,193,203,214,224,4,18,29,39,50,60,70,81,91,102,112,123,139,193,203,214,7,23,34,44,55,65,76,86,96,107,117,137,169,193,203,214,224,1,14,27,66,105,118,131,145,159,169,180,198,214)
LED_Y = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,27,34,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,40,52,52,52,52,52,52,52,52,52,52,52,52,52,52,52,52,58,64,64,64,64,64,64,64,64,64,64,64,64,64)
WIDTH, HEIGHT = 224, 64
ASPECT = HEIGHT / WIDTH
SLANT_LINE = -0.35
# Each key's distance across Omarchy's slant, which leans like '/'
ACROSS = tuple(x - (WIDTH / 2 + SLANT_LINE * (y - HEIGHT / 2)) for x, y in zip(LED_X, LED_Y))

# LEDs held at a fixed (hue, saturation), 0-255 each, whatever the scene
# does: for a key whose LED has partly failed. For example, a key whose blue
# has died shows green in the sky; {103: (170, 255)} keeps the left arrow
# (LED 103) at full blue, which leaves it dark instead.
DEAD_BLUE = {}

SCENE = "sky"   # "sky", or "gradient" for the earlier look

# The sky
CLOUD_SAT = 0.08            # a cloud's heart: nearly white, the brightest the board gets
CLOUD_COVER = (0.47, 0.74)  # noise values where a cloud starts, and where it is solid
CLOUD_SCALE = 2.6           # cloud shapes across the board
WIND = (0.030, -0.008)      # board widths per second, toward the upper right: 30-odd s to cross
BOIL = 0.025                # how fast the clouds change shape
WALL_CLOUD = 0.35           # how much of the wallpaper's own cloud band shows through
GLOW_SAT = 0.70
GLOW_TINT = 0.6             # how far the corner keys lean to lilac (fixed: only their light breathes)
GLOW_LIGHT = 0.30           # how much whiter the corner gets as it breathes in
SKY_VIOLET = 7 / 360        # at full color the LEDs show this sky azure; lean it to periwinkle
SKY_SAT_MAX = 0.90          # the deepest the clear sky goes: the LEDs step coarsely near full color
GLOW_AT = (0.02, 1.1)       # the lilac corner (u, v), just off the lower left
GLOW_REACH = 0.32           # in board widths
GLOW_BREATH = 12.0          # seconds, on the wall clock, like the desktop's corner
LEVELS = 0                  # 0: smooth; 16 would give each key 4 bits, dithered
REROLL = 3.0                # seconds between a key's dither re-rolls

# The Hikari 99 sky, baked from the sky-99 theme and its wallpaper on
# 2026-09-30: fixed on purpose, the board does not follow theme changes.
SKY_LIGHT = (0.714, 0.028)   # bright_foreground: the clouds
SKY_LILAC = (0.752, 0.700)   # bright_magenta: the corner
SKY_DEEP = (0.635, 1.000)    # accent at full color: dim on an LED
# Per LED: the clear sky's hue and saturation there, and how much of the
# wallpaper's own cloud band lies over it
SKY_KEYS = (
    (0.648, 0.954, 0.000), (0.649, 0.953, 0.000), (0.653, 0.954, 0.000), (0.654, 0.950, 0.000), (0.656, 0.947, 0.000), (0.652, 0.956, 0.000),
    (0.654, 0.949, 0.000), (0.657, 0.948, 0.000), (0.659, 0.937, 0.000), (0.648, 0.890, 0.029), (0.636, 0.905, 0.006), (0.642, 0.922, 0.000),
    (0.644, 0.947, 0.000), (0.632, 0.929, 0.000), (0.636, 0.960, 0.000), (0.636, 0.960, 0.000), (0.636, 0.960, 0.000), (0.636, 0.960, 0.000),
    (0.636, 0.960, 0.000), (0.637, 0.960, 0.000), (0.649, 0.939, 0.000), (0.646, 0.943, 0.000), (0.652, 0.936, 0.000), (0.656, 0.916, 0.000),
    (0.659, 0.869, 0.086), (0.661, 0.890, 0.023), (0.663, 0.906, 0.003), (0.655, 0.925, 0.000), (0.649, 0.929, 0.000), (0.645, 0.910, 0.001),
    (0.649, 0.846, 0.213), (0.649, 0.836, 0.288), (0.647, 0.854, 0.158), (0.646, 0.916, 0.000), (0.637, 0.931, 0.000), (0.635, 0.941, 0.000),
    (0.629, 0.959, 0.000), (0.628, 0.960, 0.000), (0.628, 0.960, 0.000), (0.632, 0.960, 0.000), (0.631, 0.960, 0.000), (0.644, 0.933, 0.000),
    (0.651, 0.911, 0.001), (0.655, 0.892, 0.021), (0.663, 0.861, 0.112), (0.671, 0.831, 0.281), (0.668, 0.861, 0.108), (0.656, 0.900, 0.009),
    (0.647, 0.913, 0.000), (0.647, 0.883, 0.047), (0.642, 0.862, 0.135), (0.647, 0.834, 0.314), (0.657, 0.813, 0.475), (0.652, 0.841, 0.229),
    (0.650, 0.875, 0.062), (0.636, 0.922, 0.000), (0.632, 0.946, 0.000), (0.626, 0.956, 0.000), (0.624, 0.960, 0.000), (0.625, 0.960, 0.000),
    (0.628, 0.960, 0.000), (0.627, 0.960, 0.000), (0.653, 0.869, 0.097), (0.666, 0.832, 0.301), (0.675, 0.804, 0.551), (0.679, 0.813, 0.440),
    (0.682, 0.800, 0.591), (0.668, 0.825, 0.357), (0.660, 0.831, 0.320), (0.655, 0.851, 0.186), (0.654, 0.846, 0.207), (0.644, 0.848, 0.217),
    (0.647, 0.852, 0.184), (0.646, 0.832, 0.327), (0.639, 0.837, 0.300), (0.617, 0.959, 0.000), (0.623, 0.960, 0.000), (0.627, 0.960, 0.000),
    (0.679, 0.815, 0.441), (0.696, 0.798, 0.611), (0.696, 0.803, 0.546), (0.709, 0.804, 0.546), (0.696, 0.807, 0.494), (0.692, 0.811, 0.452),
    (0.707, 0.797, 0.634), (0.693, 0.789, 0.744), (0.663, 0.812, 0.492), (0.645, 0.839, 0.281), (0.632, 0.848, 0.239), (0.622, 0.876, 0.091),
    (0.638, 0.812, 0.531), (0.614, 0.960, 0.000), (0.617, 0.960, 0.000), (0.622, 0.960, 0.000), (0.613, 0.960, 0.000), (0.713, 0.803, 0.576),
    (0.731, 0.793, 0.727), (0.755, 0.791, 0.780), (0.752, 0.788, 0.822), (0.625, 0.886, 0.050), (0.623, 0.886, 0.051), (0.618, 0.915, 0.000),
    (0.611, 0.937, 0.000), (0.615, 0.905, 0.007), (0.615, 0.868, 0.134), (0.611, 0.921, 0.000), (0.613, 0.960, 0.000), (0.614, 0.960, 0.000),
)

# Gradient: theme colors it runs through, in order
GRADIENT = ("accent", "blue", "cyan", "magenta", "bright_magenta")
GRADIENT_SPAN = 1.6      # stops across the board
GRADIENT_PERIOD = 20.0   # seconds to flow one stop
SATURATION_GAIN = 5.0    # frosted white caps wash pastels out to white; pull them well back

# Clouds of light: (speed across the board per second, radius, height,
# vertical sway, sway period, swell period, phase)
CLOUDS = (
    (0.075, 0.28, 0.45, 0.30, 11.0, 7.0, 0.00),
    (0.110, 0.22, 0.60, 0.35, 9.0, 5.0, 0.45),
    (0.050, 0.34, 0.35, 0.25, 15.0, 9.0, 0.80),
)
GLOW_SOFTEN = 0.12       # saturation kept at a cloud's heart
DEEPEN = 0.5             # how far keys between clouds sink toward full color,
                         # scaled by the color's own saturation so pastels stay soft

# Breathing, in perceived brightness (LED duty is this to the power 2.2)
BREATH = ((7.0, 0.30), (17.0, 0.15))  # (period, depth): two rhythms that rarely line up
GAMMA = 2.2
MIN_BRIGHTNESS = 40  # below 32 the LED driver shuts off and the board blinks
BOARD_BRIGHTNESS = 255  # the sky's: the board's own brightness, not the knob's (None: follow the knob)
KNOB_TOLERANCE = 4

# Theme change: breathe out, reveal, bloom
OUT_TIME, REVEAL_TIME, BLOOM_TIME = 1.2, 2.4, 1.6
DIM_LEVEL = 0.5
REVEAL_RISE = 0.15
SLANT, FEATHER = -0.35, 40

FPS = 30

# The lock screen (Hikari) talks to this over a socket
SOCKET = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "keychron-glow.sock")
LOCK_LEVEL = 0.62        # perceived brightness while locked
LOCK_BREATH_DEPTH = 0.25
LOCK_FADE = 2.0          # seconds into and out of lock mode
SLEEP_FADE = 1.5         # screen blanked: down to the board's lowest
LOCK_SILENCE = 12.0      # no word from the lock screen this long: back to normal
KEY_WAVE = 0.9           # a key's light crossing the board
FAIL_TIME = 1.8          # a wrong password's shadow crossing it
UNLOCK_PART, UNLOCK_SETTLE = 1.15, 0.85   # same timing as the screen
STAR_TIME = 2.6
# Only a real lock counts: the explorer draws designs full size for its
# previews, and those talk to this socket too. Asked of the lock service.
LOCK_CHECK = ("/usr/share/omarchy/bin/omarchy-shell", "lock", "isLocked")
LOCK_CHECK_EVERY = 5.0

# Keychron / VIA raw HID. Only the board the LED map above is for: the Q6 Max,
# ANSI with knob, on its cable (another model would get its keys scrambled)
BOARD_ID = "HID_ID=0003:00003434:00000860"
KC_RGB = 0xA8
KC_SAVE, KC_SET_TYPE, KC_SET_COLOR = 0x02, 0x08, 0x0A
VIA_SET, VIA_GET, VIA_SAVE = 0x07, 0x08, 0x09
RGB_MATRIX, BRIGHTNESS, EFFECT = 0x03, 0x01, 0x02
PER_KEY_RGB, PER_KEY_SOLID = 23, 0
CHUNK = 9


class Disconnected(Exception):
    pass


def via_node():
    for node in glob.glob("/sys/class/hidraw/hidraw*"):
        try:
            with open(f"{node}/device/uevent") as f:
                if BOARD_ID not in f.read():
                    continue
            with open(f"{node}/device/report_descriptor", "rb") as f:
                if f.read(3) == b"\x06\x60\xff":
                    return "/dev/" + os.path.basename(node)
        except OSError:
            pass
    return None


class Keyboard:
    def __init__(self, path):
        self.fd = os.open(path, os.O_RDWR)
        self.sent = [None] * len(LED_X)

    def close(self):
        os.close(self.fd)

    def send(self, *data):
        """Write without waiting; the kernel blocks until the keyboard takes it."""
        try:
            os.write(self.fd, b"\0" + bytes(data).ljust(32, b"\0"))
        except OSError:
            raise Disconnected

    def drain(self):
        try:
            while select.select([self.fd], [], [], 0)[0]:
                os.read(self.fd, 32)
        except OSError:
            raise Disconnected

    def cmd(self, *data):
        """Write and wait for the matching reply."""
        self.drain()
        self.send(*data)
        try:
            deadline = time.monotonic() + 1.0
            while (left := deadline - time.monotonic()) > 0:
                if not select.select([self.fd], [], [], left)[0]:
                    break
                reply = os.read(self.fd, 32)
                if reply[0] == data[0] and (data[0] != KC_RGB or reply[1] == data[1]):
                    return reply
        except OSError:
            pass
        raise Disconnected

    def brightness(self):
        return self.cmd(VIA_GET, RGB_MATRIX, BRIGHTNESS)[3]

    def set_brightness(self, value):
        self.send(VIA_SET, RGB_MATRIX, BRIGHTNESS, value)

    def set_colors(self, colors):
        for start in range(0, len(colors), CHUNK):
            chunk = colors[start:start + CHUNK]
            if all(unchanged(a, b) for a, b in zip(self.sent[start:start + CHUNK], chunk)):
                continue
            payload = [v for h, s in chunk for v in (h, s, 255)]
            self.send(KC_RGB, KC_SET_COLOR, start, len(chunk), *payload)
            self.sent[start:start + CHUNK] = chunk
        self.drain()

    def per_key_mode(self):
        self.cmd(KC_RGB, KC_SET_TYPE, PER_KEY_SOLID)
        if self.cmd(VIA_GET, RGB_MATRIX, EFFECT)[3] != PER_KEY_RGB:
            self.cmd(VIA_SET, RGB_MATRIX, EFFECT, PER_KEY_RGB)

    def save(self, peak):
        self.cmd(VIA_SET, RGB_MATRIX, BRIGHTNESS, peak)
        self.cmd(KC_RGB, KC_SAVE)
        self.cmd(VIA_SAVE, RGB_MATRIX)


def unchanged(sent, new):
    """A step of one in hue or saturation is invisible; skip sending it."""
    return sent is not None and (sent[0] - new[0]) % 256 in (0, 1, 255) and abs(sent[1] - new[1]) <= 1


def rgb(hex_color):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4))


def smoothstep(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


def mix(a, b, m):
    """Blend two (h, s) colors, taking hue the short way round."""
    dh = (b[0] - a[0] + 0.5) % 1.0 - 0.5
    return ((a[0] + dh * m) % 1.0, a[1] + (b[1] - a[1]) * m)


def duty(peak, perceived):
    """Brightness to write for a share of the peak. The driver's floor is
    kept out of the curve instead of clipped at the bottom of it: with the
    knob low, anything dimmer than the floor would otherwise sit flat on it."""
    p = max(0.0, perceived)
    return max(MIN_BRIGHTNESS, min(255, round(MIN_BRIGHTNESS + (peak - MIN_BRIGHTNESS) * p ** GAMMA)))


def undo_duty(written, actual, peak):
    """The peak that would have produced `actual` where `written` was asked
    for: how a turn of the knob is read back."""
    span = written - MIN_BRIGHTNESS
    if span <= 0:
        return max(MIN_BRIGHTNESS, min(255, actual))
    share = span / max(1, peak - MIN_BRIGHTNESS)
    return max(MIN_BRIGHTNESS, min(255, round(MIN_BRIGHTNESS + (actual - MIN_BRIGHTNESS) / max(0.05, share))))


def breath(t):
    """Perceived brightness for the resting breath; 1.0 at t = 0."""
    return 1.0 - sum(depth * (0.5 - 0.5 * math.cos(2 * math.pi * t / period)) for period, depth in BREATH)


PERM = random.Random(99).sample(range(256), 256)


def lattice(ix, iy):
    return PERM[(PERM[ix & 255] + iy) & 255] / 255.0


def vnoise(x, y):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = lattice(ix, iy), lattice(ix + 1, iy)
    c, d = lattice(ix, iy + 1), lattice(ix + 1, iy + 1)
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy


def fbm(x, y, octaves=4):
    v, amp = 0.0, 0.5
    for _ in range(octaves):
        v += amp * vnoise(x, y)
        x, y = x * 2.03 + 17.1, y * 2.03 + 5.3
        amp *= 0.5
    return v


def ramp(e0, e1, x):
    return smoothstep((x - e0) / (e1 - e0))


class SkyScene:
    """The Hikari 99 sky, as colors at any moment."""

    breathes = False

    def __init__(self):
        self.light = SKY_LIGHT
        self.lilac = SKY_LILAC
        self.deep = SKY_DEEP
        self.base = SKY_KEYS
        # Board positions in board widths, the lilac corner's reach, and each
        # key's own moment to re-roll its dither
        self.pos = [(x / WIDTH, y / WIDTH) for x, y in zip(LED_X, LED_Y)]
        gx, gy = GLOW_AT[0], GLOW_AT[1] * ASPECT
        self.corner = [math.exp(-((u - gx) ** 2 + (w - gy) ** 2) / GLOW_REACH ** 2) for u, w in self.pos]
        self.phase = [(math.sin(i * 12.9898) * 43758.5453) % 1.0 for i in range(len(LED_X))]
        # Each key's color in clear sky, the lilac corner leaned in. The hue is
        # fixed from here on: a hue step moves the LEDs' brightest channels,
        # so everything that moves (clouds, the breath) moves only saturation.
        self.clear = []
        for (hh, ss, _), corner in zip(self.base, self.corner):
            h, s = mix(((hh + SKY_VIOLET) % 1.0, min(ss, SKY_SAT_MAX)), self.lilac, corner * GLOW_TINT)
            self.clear.append((h, s))

    @staticmethod
    def stale():
        """The sky is baked in: nothing it depends on changes."""
        return False

    def colors(self, t):
        """(h, s) floats per LED at time t."""
        out = []
        breath_in = 0.5 - 0.5 * math.cos(2 * math.pi * (time.time() % GLOW_BREATH) / GLOW_BREATH)
        top = LEVELS - 1
        for i, ((u, w), (_, _, wall_cloud), corner, (h, s)) in enumerate(zip(self.pos, self.base, self.corner, self.clear)):
            # The cloud field drifts with the wind and boils slowly
            x = u * CLOUD_SCALE - WIND[0] * CLOUD_SCALE * t
            y = w * CLOUD_SCALE - WIND[1] * CLOUD_SCALE * t
            x += 0.35 * (vnoise(x * 0.9 + t * BOIL, y * 0.9) - 0.5)
            y += 0.35 * (vnoise(x * 0.9 + 7.7, y * 0.9 - t * BOIL) - 0.5)
            drift = ramp(CLOUD_COVER[0], CLOUD_COVER[1], fbm(x, y))
            cloud = 1 - (1 - drift) * (1 - WALL_CLOUD * wall_cloud)
            # A cloud whitens the key and the corner's breath lightens it
            s += (CLOUD_SAT - s) * cloud
            s -= s * corner * GLOW_LIGHT * breath_in
            if LEVELS:
                # 4 bits, dithered: the key re-rolls its threshold at its own moment
                roll = math.floor(t / REROLL + self.phase[i])
                noise = (math.sin((i + 1) * 78.233 + roll * 12.9898) * 43758.5453) % 1.0
                s = min(top, math.floor(s * top + noise)) / top
            out.append((h, max(0.0, s)))
        return out


class GradientScene:
    """The theme's gradient and clouds of light, as colors at any moment."""

    breathes = True

    def __init__(self):
        with open(COLORS, "rb") as f:
            self.source = f.read()
        theme = tomllib.loads(self.source.decode())
        accent = theme.get("accent", "#ffffff")
        stops = []
        for name in GRADIENT:
            color = rgb(theme.get(name, accent))
            # Skip a stop that is the same color as the one before it
            if not stops or sum(abs(a - b) for a, b in zip(color, stops[-1])) > 0.12:
                stops.append(color)
        # Run out and back so the flow loops without a seam
        self.stops = stops + stops[-2:0:-1] if len(stops) > 1 else stops * 2
        h, s, _ = colorsys.rgb_to_hsv(*rgb(theme.get("bright_foreground", "#ffffff")))
        self.light = (h, s)
        # Deep, full color in the accent's hue: on an LED that reads as dim
        h, _, _ = colorsys.rgb_to_hsv(*rgb(accent))
        self.deep = (h, 1.0)

    def stale(self):
        with open(COLORS, "rb") as f:
            return f.read() != self.source

    def gradient(self, pos):
        n = len(self.stops)
        pos %= n
        i = int(pos)
        a, b = self.stops[i], self.stops[(i + 1) % n]
        m = smoothstep(pos - i)
        h, s, _ = colorsys.rgb_to_hsv(*(x + (y - x) * m for x, y in zip(a, b)))
        return h, 1 - (1 - s) ** SATURATION_GAIN

    @staticmethod
    def glow(u, w, t):
        """How much cloud light falls on a key, 0 to 1."""
        dark = 1.0
        for speed, radius, height, sway, sway_period, swell_period, phase in CLOUDS:
            travel = 1 + 2 * radius
            cx = (phase * travel + t * speed) % travel - radius
            cy = (height + sway * 0.5 * math.sin(2 * math.pi * t / sway_period + phase * 7)) * ASPECT
            swell = 0.65 + 0.35 * math.sin(2 * math.pi * t / swell_period + phase * 11)
            d2 = ((u - cx) ** 2 + (w - cy) ** 2) / radius ** 2
            dark *= 1 - swell * math.exp(-d2)
        return 1 - dark

    def colors(self, t):
        """(h, s) floats per LED at time t."""
        out = []
        flow = t / GRADIENT_PERIOD
        for x, y in zip(LED_X, LED_Y):
            u, v = x / WIDTH, y / HEIGHT
            # Along Omarchy's slant, lavender in the bottom left, with a slow wobble
            d = u * 0.85 + (1 - v) * 0.3
            d += 0.05 * math.sin(2 * math.pi * (v * 0.9 + t / 17)) + 0.04 * math.sin(2 * math.pi * (u * 1.3 - t / 23))
            h, s = self.gradient(d * GRADIENT_SPAN - flow)
            g = self.glow(u, v * ASPECT, t)
            deep = s + (1 - s) * DEEPEN * s
            soft = mix((h, s * GLOW_SOFTEN), self.light, 0.3)
            out.append(mix((h, deep), soft, g))
        return out


class LockLink:
    """The socket the lock screen writes to: one word per line."""

    def __init__(self, path):
        self.path = path
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        os.chmod(path, 0o600)
        # Remember which file is ours: a newer copy of this service may have
        # replaced it by the time this one closes
        self.inode = os.stat(path).st_ino
        self.server.listen(4)
        self.server.setblocking(False)
        self.clients = {}

    def poll(self):
        """Lines received since the last call, and whether the last client left."""
        lines, gone = [], False
        while True:
            try:
                conn, _ = self.server.accept()
            except (BlockingIOError, InterruptedError):
                break
            conn.setblocking(False)
            self.clients[conn] = b""
        for conn in list(self.clients):
            try:
                data = conn.recv(4096)
            except (BlockingIOError, InterruptedError):
                continue
            except OSError:
                data = b""
            if not data:
                conn.close()
                del self.clients[conn]
                gone = not self.clients
                continue
            *done, rest = (self.clients[conn] + data).split(b"\n")
            self.clients[conn] = rest[-512:]
            lines += [line.decode(errors="replace").split() for line in done if line.strip()]
        return lines, gone

    def close(self):
        for conn in self.clients:
            conn.close()
        self.server.close()
        try:
            if os.stat(self.path).st_ino == self.inode:
                os.unlink(self.path)
        except OSError:
            pass


class LockFx:
    """What the lock screen asks of the board, layered over the scene."""

    def __init__(self):
        self.locked = False
        self.mix = 0.0           # 0 normal .. 1 lock mode
        self.asleep = False
        self.sleep_mix = 0.0
        self.heard = 0.0
        self.origin = 0.0        # when the shared breath was at its low point
        self.period = 12.0
        self.dusk = 0.0
        self.waves = []
        self.fail_at = None
        self.unlock_at = None
        self.from_level = LOCK_LEVEL
        self.stars = []
        self.last = time.monotonic()
        self.claimed = False     # a lock screen says it is up, not yet confirmed
        self.check = None        # the running isLocked question
        self.checked = 0.0

    @staticmethod
    def number(words, i, default):
        try:
            return float(words[i])
        except (IndexError, ValueError):
            return default

    def handle(self, words, now):
        cmd = words[0]
        self.heard = now
        if cmd in ("lock", "ping"):
            if cmd == "lock":
                self.claimed = True
                self.checked = 0.0   # ask now
                self.unlock_at = None
                self.period = max(2.0, self.number(words, 2, self.period))
            phase = self.number(words, 1, None)
            if phase is not None:
                self.origin = now - phase * self.period
            self.dusk = max(0.0, min(1.0, self.number(words, 2 if cmd == "ping" else 3, self.dusk)))
        elif cmd == "wake":
            self.asleep = False
        elif cmd == "sleep":
            self.asleep = True
        elif not self.locked:
            return   # a preview, or a lock screen not yet confirmed: nothing to show
        elif cmd == "key":
            # Two screens can both report the same key; one wave is enough
            if not self.waves or now - self.waves[-1] > 0.03:
                self.waves.append(now)
        elif cmd == "fail":
            self.fail_at = now
            print("lock screen: wrong password", file=sys.stderr, flush=True)
        elif cmd == "unlock" and self.locked and self.unlock_at is None:
            # Only a new "lock" starts lock mode again after this
            self.claimed = False
            self.unlock_at = now
            self.from_level = self.lock_level(now)
            print("lock screen: unlocked", file=sys.stderr, flush=True)

    def released(self):
        """The lock screen went away. Unless it is mid-unlock, back to normal."""
        self.claimed = False
        if self.locked and self.unlock_at is None:
            self.locked = False
            print("lock screen: gone", file=sys.stderr, flush=True)

    def confirm(self, now):
        """Ask the lock service whether the session is really locked, without
        holding up the frame: start the question, collect the answer later."""
        if self.check is not None:
            if self.check.poll() is None:
                if now - self.checked > 3.0:
                    self.check.kill()
                    self.check = None
                return
            answer = (self.check.stdout.read() or b"").decode(errors="replace").strip()
            self.check = None
            if answer == "true":
                if self.claimed and not self.locked:
                    self.locked = True
                    print("lock screen: locked", file=sys.stderr, flush=True)
            elif answer == "false":
                self.claimed = False
                if self.locked and self.unlock_at is None:
                    self.locked = False
                    print("lock screen: not locked after all", file=sys.stderr, flush=True)
            return
        if not (self.claimed or self.locked) or now - self.checked < LOCK_CHECK_EVERY:
            return
        self.checked = now
        try:
            self.check = subprocess.Popen(LOCK_CHECK, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError:
            self.check = None

    def lock_level(self, now):
        b = 0.5 - 0.5 * math.cos(2 * math.pi * (now - self.origin) / self.period)
        return LOCK_LEVEL * (1 - LOCK_BREATH_DEPTH + LOCK_BREATH_DEPTH * b)

    def apply(self, scene, colors, perceived, now):
        """Colors and brightness with the lock screen's say added. The third
        value is True once, when an unlock has handed the board back."""
        dt, self.last = now - self.last, now
        handed_back = False
        self.confirm(now)

        if self.locked and self.unlock_at is None and now - self.heard > LOCK_SILENCE:
            self.released()
        if self.unlock_at is not None and now - self.unlock_at >= UNLOCK_PART + UNLOCK_SETTLE:
            self.unlock_at = None
            self.locked = self.claimed = False
            self.mix = self.sleep_mix = self.dusk = 0.0
            self.waves, self.stars, self.fail_at = [], [], None
            return colors, perceived, True

        step = dt / LOCK_FADE
        self.mix += max(-step, min(step, (1.0 if self.locked else 0.0) - self.mix))
        step = dt / SLEEP_FADE
        self.sleep_mix += max(-step, min(step, (1.0 if self.locked and self.asleep else 0.0) - self.sleep_mix))
        if self.mix <= 0.0 and not self.waves and self.fail_at is None:
            return colors, perceived, handed_back

        m = smoothstep(self.mix)
        out = list(colors)

        # Away: deeper and dimmer as the screen's sky goes to night
        if self.dusk > 0:
            deepen = self.dusk * 0.5 * m
            out = [mix(c, scene.deep, deepen) for c in out]

        # Night: now and then a key twinkles, like the stars on the screen
        if self.dusk > 0.55 and not self.asleep:
            rate = (self.dusk - 0.55) / 0.45 * 0.7
            if random.random() < rate * dt and len(self.stars) < 5:
                led = random.choice([i for i in range(len(LED_X)) if i not in DEAD_BLUE])
                self.stars.append((led, now))
        self.stars = [(led, at) for led, at in self.stars if now - at < STAR_TIME]
        for led, at in self.stars:
            env = math.sin(math.pi * (now - at) / STAR_TIME) ** 2
            out[led] = mix(out[led], scene.light, 0.85 * env * m)

        # Keys: light crossing the board along the slant
        self.waves = [at for at in self.waves if now - at < KEY_WAVE]
        bump = 0.0
        for at in self.waves:
            u = (now - at) / KEY_WAVE
            front = -140 + u * 280
            fade = 1 - 0.5 * u
            for i, d in enumerate(ACROSS):
                band = math.exp(-((d - front) / 16) ** 2) * fade
                if band > 0.02:
                    out[i] = mix(out[i], scene.light, 0.7 * band)
            bump += 0.05 * math.sin(math.pi * u)

        level = perceived + (self.lock_level(now) - perceived) * m

        # A wrong password: a shadow passing over, as on the screen
        if self.fail_at is not None:
            u = (now - self.fail_at) / FAIL_TIME
            if u >= 1:
                self.fail_at = None
            else:
                front = -150 + u * 300
                for i, d in enumerate(ACROSS):
                    band = math.exp(-((d - front) / 28) ** 2)
                    if band > 0.02:
                        out[i] = mix(out[i], scene.deep, 0.8 * band)
                level *= 1 - 0.3 * math.exp(-((u - 0.5) / 0.2) ** 2)

        # The unlock: light spreads out from the slant, the board blooms, and
        # settles at the brightness a fresh breath starts from
        if self.unlock_at is not None:
            e = now - self.unlock_at
            reach = WIDTH / 2 + abs(SLANT_LINE) * HEIGHT / 2 + FEATHER
            if e < UNLOCK_PART:
                p = 1 - (1 - e / UNLOCK_PART) ** 3   # like the screen's OutCubic
                spread = reach * p
                for i, d in enumerate(ACROSS):
                    mm = smoothstep((spread - abs(d)) / FEATHER)
                    out[i] = mix(out[i], scene.light, math.sin(math.pi * mm) * 0.8)
                level = self.from_level + (1.12 - self.from_level) * p
            else:
                p = smoothstep((e - UNLOCK_PART) / UNLOCK_SETTLE)
                level = 1.12 - 0.12 * p
            return out, level, handed_back

        level = level + bump
        level = level * (1 - self.sleep_mix)
        return out, level, handed_back


def make_scene():
    return SkyScene() if SCENE == "sky" else GradientScene()


def resting(scene, t):
    """The board's brightness at rest: the gradient breathes, the sky holds still."""
    return breath(t) if scene.breathes else 1.0


def to_bytes(colors):
    out = [(round(h * 255) % 256, round(s * 255)) for h, s in colors]
    for i, fixed in DEAD_BLUE.items():
        out[i] = fixed
    return out


class Glow:
    def __init__(self):
        self.running = True
        self.peak = BOARD_BRIGHTNESS if SCENE == "sky" and BOARD_BRIGHTNESS else self.load_peak()
        self.written = None
        self.last_check = 0.0
        self.link = None
        self.fx = LockFx()

    def load_peak(self):
        try:
            with open(PEAK_FILE) as f:
                return max(MIN_BRIGHTNESS, min(255, int(f.read())))
        except (OSError, ValueError):
            return None

    def store_peak(self):
        os.makedirs(os.path.dirname(PEAK_FILE), exist_ok=True)
        with open(PEAK_FILE, "w") as f:
            f.write(str(self.peak))

    def level(self, kb, perceived):
        """Set brightness as a share of the peak, following the user's knob
        (or, for the sky, holding its own)."""
        now = time.monotonic()
        if self.written is not None and now - self.last_check > 0.5:
            self.last_check = now
            actual = kb.brightness()
            # The firmware rounds what it is given by a step; the knob moves
            # brightness in steps of 16
            if abs(actual - self.written) > KNOB_TOLERANCE and SCENE == "sky" and BOARD_BRIGHTNESS:
                # The sky owns the brightness: put it back
                self.written = None
            elif abs(actual - self.written) > KNOB_TOLERANCE:
                peak = undo_duty(self.written, actual, self.peak)
                print(f"brightness set on the keyboard: {actual} (expected {self.written}); "
                      f"peak {self.peak} -> {peak}", file=sys.stderr, flush=True)
                self.peak = peak
                self.store_peak()
                kb.save(self.peak)
                self.written = self.peak
        value = duty(self.peak, perceived)
        if value != self.written:
            kb.set_brightness(value)
            self.written = value

    def transition(self, kb, old, new, clock, start_level):
        """Breathe out, roll the new gradient in on a slant, bloom back."""
        reach = WIDTH / 2 + abs(SLANT) * HEIGHT / 2 + FEATHER
        total = OUT_TIME + REVEAL_TIME + BLOOM_TIME
        began = time.monotonic()
        frame = 0
        while self.running:
            e = time.monotonic() - began
            if e >= total:
                return
            t = clock()
            if e < OUT_TIME:
                p = smoothstep(e / OUT_TIME)
                perceived = start_level + (DIM_LEVEL - start_level) * p
                colors = old.colors(t)
            elif e < OUT_TIME + REVEAL_TIME:
                p = smoothstep((e - OUT_TIME) / REVEAL_TIME)
                perceived = DIM_LEVEL + REVEAL_RISE * p
                spread = reach * p
                old_now, new_now = old.colors(t), new.colors(t)
                colors = []
                for i, (x, y) in enumerate(zip(LED_X, LED_Y)):
                    d = abs(x - (WIDTH / 2 + SLANT * (y - HEIGHT / 2)))
                    m = smoothstep((spread - d) / FEATHER)
                    # A soft light rides the front of the reveal
                    c = mix(old_now[i], new_now[i], m)
                    colors.append(mix(c, new.light, math.sin(math.pi * m) * 0.7))
            else:
                p = (e - OUT_TIME - REVEAL_TIME) / BLOOM_TIME
                perceived = 1 + 0.12 * math.sin(math.pi * p) - (1 - smoothstep(p)) * (1 - DIM_LEVEL - REVEAL_RISE)
                colors = new.colors(t)
            kb.set_colors(to_bytes(colors))
            self.level(kb, max(0.0, min(1.12, perceived)))
            frame += 1
            time.sleep(max(0.0, began + frame / FPS - time.monotonic()))

    def run(self, once=False):
        scene = make_scene()
        start = time.monotonic()
        clock = lambda: time.monotonic() - start
        while self.running:
            path = via_node()
            if not path:
                time.sleep(2)
                continue
            try:
                kb = Keyboard(path)
            except OSError:
                time.sleep(2)
                continue
            try:
                if self.peak is None:
                    self.peak = max(MIN_BRIGHTNESS, kb.brightness())
                    self.store_peak()
                self.written = None
                kb.set_colors(to_bytes(scene.colors(clock())))
                kb.per_key_mode()
                kb.save(self.peak)
                if once:
                    return
                self.written = self.peak
                breath_start = clock()
                last_theme_check = 0.0
                frame_start = time.monotonic()
                frame = 0
                while self.running:
                    t = clock()
                    if t - last_theme_check > 0.5:
                        last_theme_check = t
                        try:
                            new = make_scene() if scene.stale() else None
                        except (OSError, ValueError):
                            new = None  # mid-write; look again shortly
                        if new:
                            self.transition(kb, scene, new, clock, resting(scene, t - breath_start))
                            scene = new
                            kb.save(self.peak)
                            self.written = self.peak
                            breath_start = clock()
                            frame_start, frame = time.monotonic(), 0
                    colors, perceived = scene.colors(t), resting(scene, t - breath_start)
                    if self.link:
                        now = time.monotonic()
                        lines, gone = self.link.poll()
                        for words in lines:
                            self.fx.handle(words, now)
                        if gone:
                            self.fx.released()
                        colors, perceived, handed_back = self.fx.apply(scene, colors, perceived, now)
                        if handed_back:
                            breath_start = clock()
                    kb.set_colors(to_bytes(colors))
                    self.level(kb, max(0.0, min(1.12, perceived)))
                    frame += 1
                    time.sleep(max(0.0, frame_start + frame / FPS - time.monotonic()))
                kb.save(self.peak)
            except Disconnected:
                self.written = None
                time.sleep(2)
            finally:
                kb.close()


def main():
    glow = Glow()

    def stop(*_):
        glow.running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    once = "--once" in sys.argv
    if not once:
        try:
            glow.link = LockLink(SOCKET)
        except OSError as e:
            print(f"lock screen link unavailable: {e}", file=sys.stderr, flush=True)
    try:
        glow.run(once=once)
    finally:
        if glow.link:
            glow.link.close()


if __name__ == "__main__":
    main()
