"""Draws the 1024x1024 app icon: a road coloured by the app's temperature
bands (cold blue at the bottom to hot red at the horizon) under a sun, on the
app's dark background. Opaque RGB, as App Store Connect requires.

Usage: python3 tools/app-icon/make_icon.py RoadTripWeather/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 2048  # draw at 2x, downsample for smooth edges
BANDS = ["#3b82f6", "#22c55e", "#eab308", "#f97316", "#ef4444"]  # TemperatureScale.default


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def band_color(t):
    """t in [0,1] across the five band colours."""
    cols = [hex_rgb(c) for c in BANDS]
    x = t * (len(cols) - 1)
    i = min(int(x), len(cols) - 2)
    return lerp(cols[i], cols[i + 1], x - i)


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u ** 3 * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t ** 3 * p3[k] for k in range(2))


img = Image.new("RGB", (S, S))
px = img.load()
top, bottom = hex_rgb("#1b2a4a"), hex_rgb("#0b1220")
for y in range(S):
    c = lerp(top, bottom, y / (S - 1))
    for x in range(S):
        px[x, y] = c

# Sun with a soft glow, upper right.
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse((1270, 250, 1790, 770), fill=150)
glow = glow.filter(ImageFilter.GaussianBlur(90))
img.paste(Image.new("RGB", (S, S), hex_rgb("#fbbf24")), (0, 0), glow)
ImageDraw.Draw(img).ellipse((1390, 370, 1670, 650), fill=hex_rgb("#fbbf24"))

# Horizon line.
d = ImageDraw.Draw(img)
d.rectangle((0, 1010, S, 1018), fill=hex_rgb("#24365e"))

# Road: an S-curve from the bottom edge to the horizon, tapering with
# distance and coloured cold → hot along its length.
p0, p1, p2, p3 = (1024, 2150), (1700, 1600), (500, 1250), (1060, 1014)
steps = 900
for i in range(steps + 1):
    t = i / steps
    x, y = bezier(p0, p1, p2, p3, t)
    r = 300 * (1 - t) ** 1.35 + 10
    d.ellipse((x - r, y - r, x + r, y + r), fill=band_color(t))

# Dashed centre line, also tapering.
for i in range(steps + 1):
    t = i / steps
    if int(t * 14) % 2 == 1 or t > 0.93:
        continue
    x, y = bezier(p0, p1, p2, p3, t)
    r = 22 * (1 - t) ** 1.35 + 1.5
    d.ellipse((x - r, y - r, x + r, y + r), fill=(245, 248, 255))

img = img.resize((1024, 1024), Image.LANCZOS)
img.save(sys.argv[1], "PNG")
print("wrote", sys.argv[1], img.size, img.mode)
