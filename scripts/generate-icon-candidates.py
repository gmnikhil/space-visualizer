#!/usr/bin/env python3
"""Generate a review sheet only; requires Pillow. Does not change AppIcon."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

DEST = Path(__file__).resolve().parent.parent / 'SpaceVisualizerApp/Resources/IconCandidates'
DEST.mkdir(parents=True, exist_ok=True)
S = 768
PURPLE, MINT, ORANGE = (177, 113, 255), (104, 240, 205), (255, 169, 101)

def tile():
    im = Image.new('RGBA', (S, S))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((30, 30, S-30, S-30), radius=160, fill=(15, 12, 31), outline=(49, 39, 70), width=2)
    return im

def path(draw, points, color, width=5):
    draw.line(points, fill=color, width=width, joint='curve')

def ellipse_points(rx, ry, angle, phase=0, ripple=0):
    a = math.radians(angle)
    points=[]
    for i in range(721):
        t=i*math.pi/360
        r=1+ripple*math.sin(6*t+phase)
        x,y=rx*math.cos(t)*r,ry*math.sin(t)*r
        points.append((384+x*math.cos(a)-y*math.sin(a),384+x*math.sin(a)+y*math.cos(a)))
    return points

names=['Orbital harmony', 'Resonant halo', 'Wave horizon', 'Spatial bloom', 'Quiet eclipse']
images=[]
for candidate in range(5):
    im=tile()
    ink=Image.new('RGBA',im.size)
    d=ImageDraw.Draw(ink)
    if candidate==0:
        for j,(a,c) in enumerate(zip((-35,25,85),(PURPLE,MINT,ORANGE))):
            for band in range(2):
                path(d,ellipse_points(242-band*18,104-band*12,a,ripple=.018),(*c,255 if band==0 else 115),6 if band==0 else 3)
    elif candidate==1:
        for band in range(9):
            points=[]
            for i in range(721):
                t=i*math.pi/360
                r=185+band*8+14*math.sin(5*t+band*.27)+8*math.sin(9*t)
                points.append((384+r*math.cos(t),384+r*math.sin(t)))
            c=PURPLE if band<4 else MINT if band<7 else ORANGE
            path(d,points,(*c,220),4)
    elif candidate==2:
        for row in range(17):
            points=[]
            for x in range(150,619):
                u=(x-384)/234
                envelope=(1-u*u)**1.3
                y=390+(row-8)*15+envelope*(48*math.sin(u*math.pi*2+row*.19))
                points.append((x,y))
            c=PURPLE if row<6 else MINT if row<12 else ORANGE
            path(d,points,(*c,235),5)
    elif candidate==3:
        for j in range(12):
            c=(PURPLE,MINT,ORANGE)[j%3]
            path(d,ellipse_points(237,82,j*15),(*c,180),4)
    else:
        # A restrained orbit encircling a shaded, unlit planet.
        d.ellipse((224,224,544,544),fill=(36,23,63),outline=(*PURPLE,230),width=5)
        path(d,ellipse_points(261,86,-28),(*MINT,255),7)
        path(d,ellipse_points(272,98,-28),(*PURPLE,140),3)
        d.ellipse((565,264,585,284),fill=(*ORANGE,255))
    im=Image.alpha_composite(im,ink.filter(ImageFilter.GaussianBlur(11)))
    im=Image.alpha_composite(im,ink)
    im.save(DEST/f'candidate-{candidate+1}.png')
    images.append(im)

sheet=Image.new('RGB',(1500,1060),(23,23,29))
d=ImageDraw.Draw(sheet)
try:
    font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',25)
except OSError:
    font=ImageFont.load_default(size=25)
for i,im in enumerate(images):
    x=(i%3)*500
    y=(i//3)*520
    preview=im.resize((460,460),Image.Resampling.LANCZOS)
    sheet.paste(preview,(x+20,y+5),preview)
    d.text((x+250,y+480),f'{i+1}. {names[i]}',font=font,fill=(236,232,245),anchor='mm')
sheet.save(DEST/'candidates.jpg',quality=95)
print(DEST/'candidates.jpg')
