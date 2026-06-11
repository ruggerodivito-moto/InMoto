# Genera l'icona dell'app InMoto (1024x1024, senza alpha).
# Design: sfondo antracite, strada a S arancione con linea di mezzeria
# tratteggiata bianca e pin di destinazione.
#
# Uso:  python tools/genera_icona.py
# Output: InMoto/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png

from PIL import Image, ImageDraw
import os

S = 1024
SS = 4  # supersampling per bordi morbidi
W = S * SS

img = Image.new("RGB", (W, W))
draw = ImageDraw.Draw(img)

# ── Sfondo: gradiente verticale antracite ────────────────────────────────────
top = (44, 44, 50)
bottom = (22, 22, 26)
for y in range(W):
    t = y / (W - 1)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    draw.line([(0, y), (W, y)], fill=c)


def bezier(p0, p1, p2, p3, n=400):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x * SS, y * SS))
    return pts


# ── Strada a S: dal basso-sinistra all'alto-destra ───────────────────────────
road = bezier((170, 1130), (640, 740), (300, 360), (840, -80))

ROAD_W = 175 * SS
ORANGE = (255, 140, 26)
ORANGE_DARK = (224, 102, 0)

# ombra leggera della strada
for x, y in road:
    draw.ellipse([x - ROAD_W / 2 - 14 * SS, y - ROAD_W / 2 - 14 * SS + 10 * SS,
                  x + ROAD_W / 2 + 14 * SS, y + ROAD_W / 2 + 14 * SS + 10 * SS],
                 fill=(14, 14, 17))

# corpo strada arancione (gradiente lungo la curva: scuro→acceso)
n = len(road)
for i, (x, y) in enumerate(road):
    t = i / (n - 1)
    c = tuple(int(ORANGE_DARK[k] + (ORANGE[k] - ORANGE_DARK[k]) * t) for k in range(3))
    draw.ellipse([x - ROAD_W / 2, y - ROAD_W / 2, x + ROAD_W / 2, y + ROAD_W / 2], fill=c)

# ── Mezzeria tratteggiata bianca ─────────────────────────────────────────────
DASH_ON, DASH_OFF = 26, 18   # in punti della curva
LINE_W = 17 * SS
i = 0
while i < n:
    for j in range(i, min(i + DASH_ON, n)):
        x, y = road[j]
        draw.ellipse([x - LINE_W / 2, y - LINE_W / 2, x + LINE_W / 2, y + LINE_W / 2],
                     fill=(248, 248, 250))
    i += DASH_ON + DASH_OFF

# ── Pin di destinazione in cima alla strada (dentro il canvas) ───────────────
px, py = road[int(n * 0.80)]
R = 92 * SS
draw.ellipse([px - R - 10 * SS, py - R - 10 * SS, px + R + 10 * SS, py + R + 10 * SS],
             fill=(248, 248, 250))
draw.ellipse([px - R, py - R, px + R, py + R], fill=(214, 60, 34))
r2 = 36 * SS
draw.ellipse([px - r2, py - r2, px + r2, py + r2], fill=(248, 248, 250))

# ── Salva (downsample con antialiasing) ──────────────────────────────────────
img = img.resize((S, S), Image.LANCZOS)
out = os.path.join(os.path.dirname(__file__), "..",
                   "InMoto", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(out, exist_ok=True)
path = os.path.join(out, "AppIcon1024.png")
img.save(path, "PNG")
print(f"Icona salvata: {os.path.abspath(path)}")
