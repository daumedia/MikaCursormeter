#!/usr/bin/env python3
"""Baut AppIcon.iconset und AppIcon.icns aus AppIcon-master.png.

    python3 scripts/make_icon.py

AppIcon-master.png ist der 1024er Master: randfuellend und ohne transparenten
Rand. icon-source.png daneben ist das Rendering, aus dem der Master zugeschnitten
wurde — nur noetig, wenn der Master neu berechnet werden soll.

Warum randfuellend und nicht freigestellt: macOS 26 legt jedes Icon, das einen
transparenten Rand hat, als Legacy-Icon auf eine dunkle Platte und skaliert es
auf 824 von 1024 hinein. Der klassische freigestellte Squircle mit Schlagschatten
(Apple HIG bis macOS 15) wird dadurch doppelt eingerueckt und schwimmt sichtbar
auf schwarzem Grund. Ein randfuellendes Icon maskiert das System dagegen selbst
zum Squircle — so wie die System-Apps. Der Preis: unter macOS 15 fehlt diese
Maske, dort erscheint das Icon quadratisch.

Unter 256 px wird nachgeschaerft — ein reiner Downscale laesst den Clay-Look bei
16 und 32 px jede Kante verlieren. Die Werte je Groesse stehen in GROESSEN.
"""
import os
import subprocess
import sys

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Pillow fehlt: python3 -m pip install Pillow")

# Dateiname: (Kantenlaenge, Schaerfung als (radius, percent) oder None)
GROESSEN = {
    "icon_16x16.png": (16, (0.6, 130)),
    "icon_16x16@2x.png": (32, (0.7, 110)),
    "icon_32x32.png": (32, (0.7, 110)),
    "icon_32x32@2x.png": (64, (0.8, 90)),
    "icon_128x128.png": (128, (0.9, 60)),
    "icon_128x128@2x.png": (256, None),
    "icon_256x256.png": (256, None),
    "icon_256x256@2x.png": (512, None),
    "icon_512x512.png": (512, None),
    "icon_512x512@2x.png": (1024, None),
}

hier = os.path.dirname(os.path.abspath(__file__))
master_pfad = os.path.join(hier, "AppIcon-master.png")
iconset = os.path.join(hier, "AppIcon.iconset")

if not os.path.exists(master_pfad):
    sys.exit(f"✗ {master_pfad} fehlt")

master = Image.open(master_pfad).convert("RGBA")
if master.size != (1024, 1024):
    sys.exit(f"✗ Master ist {master.size[0]}x{master.size[1]}, erwartet 1024x1024")

os.makedirs(iconset, exist_ok=True)

for name, (size, schaerfe) in GROESSEN.items():
    img = master if size == 1024 else master.resize((size, size), Image.LANCZOS)
    if schaerfe:
        rgb, alpha = img.convert("RGB"), img.split()[3]
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=schaerfe[0], percent=schaerfe[1], threshold=0))
        img = rgb.convert("RGBA")
        img.putalpha(alpha)
    img.save(os.path.join(iconset, name))
    print(f"✓ {name} ({size}px)")

master.save(os.path.join(hier, "AppIcon.png"))
print("✓ AppIcon.png (1024px Preview)")

subprocess.run(["/usr/bin/iconutil", "-c", "icns", iconset,
                "-o", os.path.join(hier, "AppIcon.icns")], check=True)
print("✓ AppIcon.icns generiert")
