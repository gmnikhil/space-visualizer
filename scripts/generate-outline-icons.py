#!/usr/bin/env python3
"""Flat, playful orbital logo previews; requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

DEST=Path(__file__).resolve().parent.parent/'SpaceVisualizerApp/Resources/IconCandidates'
DEST.mkdir(parents=True,exist_ok=True)
S=1600
BG=(16,13,32,255)
COLORS=[(111,239,210,255),(187,135,255,255),(255,177,113,255)]

def loop(d,rx,ry,angle,color,width=9,ripple=0):
    a=math.radians(angle); pts=[]
    for i in range(1201):
        t=i*math.pi/600
        r=1+ripple*math.sin(5*t)
        x=rx*math.cos(t)*r; y=ry*math.sin(t)*r
        pts.append((800+x*math.cos(a)-y*math.sin(a),800+x*math.sin(a)+y*math.cos(a)))
    d.line(pts,fill=color,width=width,joint='curve')

def bubble(d,x,y,r,c):
    # Hollow: same background as tile, with a friendly, single-weight contour.
    d.ellipse((x-r,y-r,x+r,y+r),fill=BG,outline=c,width=11)

def sparkle(d,x,y,r,c):
    d.line([(x-r,y),(x+r,y)],fill=c,width=8)
    d.line([(x,y-r),(x,y+r)],fill=c,width=8)

images=[]
for v in range(3):
    im=Image.new('RGBA',(S,S))
    d=ImageDraw.Draw(im)
    d.rounded_rectangle((90,90,1510,1510),radius=322,fill=BG,outline=(49,40,69),width=3)
    if v==0:
        for a,c in zip((-32,28,88),COLORS): loop(d,480,205,a,c)
        for x,y,r,c in [(392,519,65,COLORS[0]),(1083,493,49,COLORS[2]),(1061,1030,72,COLORS[2]),(679,1230,53,COLORS[1])]: bubble(d,x,y,r,c)
        # Heart sits directly on the mint orbit, with a rounded lower tip.
        heart=[]
        curves=[
            ((0,-10),(-14,-32),(-36,-22),(-28,-3)),
            ((-28,-3),(-23,8),(-10,17),(-5,21)),
            ((-5,21),(-2,24),(2,24),(5,21)),
            ((5,21),(10,17),(23,8),(28,-3)),
            ((28,-3),(36,-22),(14,-32),(0,-10)),
        ]
        for p0,p1,p2,p3 in curves:
            for step in range(61):
                t=step/60; u=1-t
                x=u**3*p0[0]+3*u*u*t*p1[0]+3*u*t*t*p2[0]+t**3*p3[0]
                y=u**3*p0[1]+3*u*u*t*p1[1]+3*u*t*t*p2[1]+t**3*p3[1]
                heart.append((1152+x,760+y))
        d.polygon(heart,fill=BG)
        d.line(heart+[heart[0]],fill=COLORS[1],width=7,joint='curve')
    elif v==1:
        for j in range(6): loop(d,445,250,j*30,COLORS[j%3],6,ripple=.018)
        for x,y,r,c in [(471,454,73,COLORS[0]),(405,971,47,COLORS[0]),(1158,748,80,COLORS[2]),(727,1215,60,COLORS[1])]: bubble(d,x,y,r,c)
        sparkle(d,976,428,22,COLORS[2])
    else:
        for a,c in zip((-35,25,85),COLORS): loop(d,470,202,a,c,11,ripple=.055)
        for x,y,r,c in [(404,617,45,COLORS[0]),(1087,467,53,COLORS[1]),(864,1214,42,COLORS[2])]: bubble(d,x,y,r,c)
        sparkle(d,1150,961,26,COLORS[2])
        sparkle(d,616,388,17,COLORS[0])
    im=im.resize((1024,1024),Image.Resampling.LANCZOS)
    im.save(DEST/f'cartoon-outline-{v+1}.png')
    images.append(im)
sheet=Image.new('RGB',(1800,665),(23,23,29)); d=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',27)
except OSError: font=ImageFont.load_default(size=27)
for i,(im,name) in enumerate(zip(images,['1. Orbit bubbles','2. Playful constellation','3. Bouncy harmony'])):
    p=im.resize((590,590),Image.Resampling.LANCZOS)
    sheet.paste(p,(600*i+5,0),p)
    d.text((600*i+300,620),name,font=font,fill=(237,233,245),anchor='mm')
sheet.save(DEST/'cartoon-outline-candidates.jpg',quality=95)
print(DEST/'cartoon-outline-candidates.jpg')
