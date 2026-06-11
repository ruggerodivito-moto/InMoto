# Genera l'icona dell'app InMoto (1024x1024, senza alpha) dal logo
# tools/Logo_Bikers.jpeg: pareggia a quadrato riempiendo con il colore
# di sfondo del logo e scala a 1024.
#
# Uso:  python tools/genera_icona.py
# Output: InMoto/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png

from PIL import Image
import os

S = 1024
here = os.path.dirname(os.path.abspath(__file__))

logo = Image.open(os.path.join(here, "Logo_Bikers.jpeg")).convert("RGB")
w, h = logo.size

# Colore di sfondo: media dei quattro angoli del logo
corners = [logo.getpixel(p) for p in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]]
bg = tuple(sum(c[i] for c in corners) // 4 for i in range(3))

# Pareggia a quadrato centrando il logo
side = max(w, h)
square = Image.new("RGB", (side, side), bg)
square.paste(logo, ((side - w) // 2, (side - h) // 2))

icon = square.resize((S, S), Image.LANCZOS)

out = os.path.join(here, "..", "InMoto", "Resources", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(out, exist_ok=True)
path = os.path.join(out, "AppIcon1024.png")
icon.save(path, "PNG")
print(f"Icona salvata: {os.path.abspath(path)}")
