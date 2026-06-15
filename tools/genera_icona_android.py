# Genera le icone launcher Android dallo STESSO logo dell'icona iOS
# (tools/Logo_Bikers.jpeg). Produce:
#  - mipmap-*/ic_launcher.png e ic_launcher_round.png  (icona legacy, quadrata,
#    stesso rendering dell'iOS: logo centrato su sfondo del logo, pareggiato a
#    quadrato);
#  - mipmap-*/ic_launcher_foreground.png  (foreground dell'adaptive icon v26+:
#    logo scalato dentro la "safe zone" su canvas trasparente);
#  - aggiorna values/colors.xml con il colore di sfondo del logo.
#
# Uso:  py -3.12 tools/genera_icona_android.py

from PIL import Image
import os

here = os.path.dirname(os.path.abspath(__file__))
res = os.path.join(here, "..", "android", "app", "src", "main", "res")

logo = Image.open(os.path.join(here, "Logo_Bikers.jpeg")).convert("RGB")
w, h = logo.size

# Colore di sfondo: media dei quattro angoli del logo (come genera_icona.py iOS)
corners = [logo.getpixel(p) for p in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]]
bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

# Logo pareggiato a quadrato (identico all'icona iOS)
side = max(w, h)
square = Image.new("RGB", (side, side), bg)
square.paste(logo, ((side - w) // 2, (side - h) // 2))

# Logo RGBA per il foreground (su canvas trasparente)
square_rgba = square.convert("RGBA")

# Densita': (cartella, dim icona legacy, dim foreground a 108dp)
densities = [
    ("mipmap-mdpi", 48, 108),
    ("mipmap-hdpi", 72, 162),
    ("mipmap-xhdpi", 96, 216),
    ("mipmap-xxhdpi", 144, 324),
    ("mipmap-xxxhdpi", 192, 432),
]

# Quota del canvas foreground occupata dal logo (resta nella safe zone ~66dp/108dp)
FG_SCALE = 0.66

for folder, leg, fg in densities:
    d = os.path.join(res, folder)
    os.makedirs(d, exist_ok=True)

    # Icona legacy quadrata
    legacy = square.resize((leg, leg), Image.LANCZOS)
    legacy.save(os.path.join(d, "ic_launcher.png"), "PNG")
    legacy.save(os.path.join(d, "ic_launcher_round.png"), "PNG")

    # Foreground adaptive: logo scalato dentro la safe zone, canvas trasparente
    canvas = Image.new("RGBA", (fg, fg), (0, 0, 0, 0))
    inner = int(fg * FG_SCALE)
    logo_fg = square_rgba.resize((inner, inner), Image.LANCZOS)
    off = (fg - inner) // 2
    canvas.paste(logo_fg, (off, off), logo_fg)
    canvas.save(os.path.join(d, "ic_launcher_foreground.png"), "PNG")

# Aggiorna il colore di sfondo dell'adaptive icon
hexbg = "#{:02X}{:02X}{:02X}".format(*bg)
colors_path = os.path.join(res, "values", "colors.xml")
with open(colors_path, "w", encoding="utf-8") as f:
    f.write('<resources>\n')
    f.write('    <color name="ic_launcher_background">{}</color>\n'.format(hexbg))
    f.write('</resources>\n')

print("Sfondo logo:", hexbg)
print("Icone Android generate in", os.path.abspath(res))
