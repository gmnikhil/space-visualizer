#!/usr/bin/env python3
"""Preview only: heavier Orbit Bubbles artwork. Requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent.parent
DEST=ROOT/'SpaceVisualizerApp/Resources/IconCandidates'
S=1600
BG=(29,24,49,255)
COLORS=[(111,239,210,255),(187,135,255,255),(255,177,113,255)]
im=Image.new('RGBA',(S,S))
d=ImageDraw.Draw(im)
d.rounded_rectangle((90,90,1510,1510),radius=322,fill=BG,outline=(66,55,88),width=4)

def point(x,y):
    return (800+(x-800)*1.15,800+(y-800)*1.15)

for angle,c in zip((-32,28,88),COLORS):
    a=math.radians(angle)
    pts=[]
    for i in range(1441):
        t=i*math.pi/720
        x,y=480*math.cos(t),205*math.sin(t)
        pts.append(point(800+x*math.cos(a)-y*math.sin(a),800+x*math.sin(a)+y*math.cos(a)))
    d.line(pts,fill=c,width=23,joint='curve')
for x,y,r,c in [(392,519,65,COLORS[0]),(1083,493,49,COLORS[2]),(1061,1030,72,COLORS[2]),(679,1230,53,COLORS[1])]:
    x,y=point(x,y); r*=1.15
    d.ellipse((x-r,y-r,x+r,y+r),fill=BG,outline=c,width=24)
curves=[
    ((0,-10),(-14,-32),(-36,-22),(-28,-3)),
    ((-28,-3),(-23,8),(-10,17),(-5,21)),
    ((-5,21),(-2,24),(2,24),(5,21)),
    ((5,21),(10,17),(23,8),(28,-3)),
    ((28,-3),(36,-22),(14,-32),(0,-10)),
]
heart=[]
for p0,p1,p2,p3 in curves:
    for step in range(81):
        t=step/80; u=1-t
        x=u**3*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t**3*p3[0]
        y=u**3*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t**3*p3[1]
        heart.append(point(1152+x*1.35,760+y*1.35))
d.polygon(heart,fill=BG)
d.line(heart+[heart[0]],fill=COLORS[1],width=17,joint='curve')
im=im.resize((1024,1024),Image.Resampling.LANCZOS)
im.save(DEST/'orbit-bubbles-dock-preview.png')
old=Image.open(ROOT/'SpaceVisualizerApp/Resources/AppIcon.png').convert('RGBA')
sheet=Image.new('RGB',(1100,750),(23,23,29)); d=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',24)
except OSError: font=ImageFont.load_default(size=24)
for i,(art,label) in enumerate([(old,'Current'),(im,'Proposed — larger & bolder')]):
    thumb=art.resize((470,470),Image.Resampling.LANCZOS)
    sheet.paste(thumb,(i*550+40,10),thumb)
    d.text((i*550+275,510),label,font=font,fill='white',anchor='mm')
    for j,size in enumerate((32,64,96)):
        thumb=art.resize((size,size),Image.Resampling.LANCZOS)
        sheet.paste(thumb,(i*550+100+j*130+(96-size)//2,560+(96-size)//2),thumb)
        d.text((i*550+148+j*130,685),f'{size}px',font=font,fill='white',anchor='mm')
sheet.save(DEST/'dock-icon-comparison.jpg',quality=95)
print(DEST/'dock-icon-comparison.jpg')
