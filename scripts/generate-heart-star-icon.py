#!/usr/bin/env python3
"""Review-only heart/star-shaped orbital outlines; requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter

DEST = Path(__file__).resolve().parent.parent / 'SpaceVisualizerApp/Resources/IconCandidates'
DEST.mkdir(parents=True, exist_ok=True)
S = 2048
im = Image.new('RGBA', (S, S))
ImageDraw.Draw(im).rounded_rectangle(
    (120,120,1928,1928), radius=410, fill=(15,12,31),
    outline=(48,38,68), width=4)

# Heart lobes flow directly into star shoulders and a tapered lower point.
# This contour IS each orbit, rather than a separate central emblem.
segments = [
    ((0,-95),(-100,-230),(-225,-190),(-170,-45)),
    ((-170,-45),(-155,-5),(-200,15),(-270,30)),
    ((-270,30),(-120,60),(-90,115),(0,270)),
    ((0,270),(90,115),(120,60),(270,30)),
    ((270,30),(200,15),(155,-5),(170,-45)),
    ((170,-45),(225,-190),(100,-230),(0,-95)),
]
contour = []
for p0,p1,p2,p3 in segments:
    for i in range(161):
        t=i/160; u=1-t
        contour.append((
            u**3*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t**3*p3[0],
            u**3*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t**3*p3[1]))

ink = Image.new('RGBA', im.size)
d = ImageDraw.Draw(ink)
colors = [(177,113,255),(104,240,205),(255,169,101)]
for index,(angle,color) in enumerate(zip((-35,25,85), colors)):
    a=math.radians(angle)
    for band in range(2):
        points=[]
        for step in range(1441):
            t=step*math.pi/720
            rx,ry=635-band*42,290-band*28
            if index == 2:
                rx,ry=500-band*34,385-band*28
            x=rx*math.cos(t)
            y=ry*math.sin(t)
            if index == 2:
                # Only the orange orbit: a gentle heart cleft at its top
                # and a softly tapered opposite end, retaining its orbit.
                delta=math.atan2(math.sin(t-math.pi), math.cos(t-math.pi))
                x += 130*math.exp(-(delta/0.30)**2)
                y *= 0.90 + 0.10*(1-math.cos(t))/2
            points.append((1024+x*math.cos(a)-y*math.sin(a),
                           1024+x*math.sin(a)+y*math.cos(a)))
        d.line(points+[points[0]], fill=(*color,245 if band==0 else 115),
               width=13 if band==0 else 5, joint='curve')
im=Image.alpha_composite(im,ink.filter(ImageFilter.GaussianBlur(22)))
im=Image.alpha_composite(im,ink)
im=im.resize((1024,1024),Image.Resampling.LANCZOS)
im.save(DEST/'orbital-heart-star-outline.png')
print(DEST/'orbital-heart-star-outline.png')
