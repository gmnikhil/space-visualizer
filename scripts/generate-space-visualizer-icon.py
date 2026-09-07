#!/usr/bin/env python3
"""Package the approved Orbit Bubbles artwork as the macOS app icon.

Requires Pillow for regeneration only. Normal builds copy the committed ICNS.
To redraw the source artwork, run generate-dock-icon-preview.py first.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / 'SpaceVisualizerApp' / 'Resources'
source = DEST / 'IconCandidates' / 'orbit-bubbles-dock-preview.png'
with Image.open(source) as image:
    icon = image.convert('RGBA')
    assert icon.size == (1024, 1024), 'Expected 1024px approved artwork'
    icon.save(DEST / 'AppIcon.png')
    icon.save(DEST / 'AppIcon.icns', format='ICNS')
print(f"Packaged approved Orbit Bubbles icon in {DEST}")
