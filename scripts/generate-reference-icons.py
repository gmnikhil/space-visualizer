#!/usr/bin/env python3
"""Reference-inspired icon previews; requires Pillow. Does not apply an icon."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

DEST=Path(__file__).resolve().parent.parent/'SpaceVisualizerApp/Resources/IconCandidates'
DEST.mkdir(parents=True,exist_ok=True)
S=1200
COLORS=[(39,224,205),(193,65,235),(255,156,54)]

def sphere(im,cx,cy,r,color):
    # Directionally lit sphere with a soft highlight and shaded lower edge.
    n=int(r*2+4)
    ball=Image.new('RGBA',(n,n))
    px=ball.load()
    for y in range(n):
        for x in range(n):
            nx=(x-r-2)/r; ny=(y-r-2)/r
            rr=nx*nx+ny*ny
            if rr>1: continue
            z=math.sqrt(1-rr)
            light=max(0,-.42*nx-.52*ny+.74*z)
            spec=math.exp(-((nx+.32)**2+(ny+.38)**2)/.036)
            shade=.12+.86*light
            px[x,y]=tuple(min(255,int(c*shade+(255-c*shade)*spec*.82)) for c in color)+(255,)
    shadow=Image.new('RGBA',im.size)
    ImageDraw.Draw(shadow).ellipse((cx-r*.9,cy+r*.96,cx+r*.9,cy+r*1.16),fill=(*color,30))
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8)))
    im.alpha_composite(ball,(int(cx-r-2),int(cy-r-2)))

def orbit(draw,rx,ry,angle,color,width=3,phase=0,wobble=0):
    a=math.radians(angle)
    points=[]
    for i in range(1001):
        t=i*2*math.pi/1000
        scale=1+wobble*math.sin(5*t+phase)
        x=rx*math.cos(t)*scale; y=ry*math.sin(t)*scale
        points.append((600+x*math.cos(a)-y*math.sin(a),600+x*math.sin(a)+y*math.cos(a)))
    draw.line(points,fill=color,width=width,joint='curve')

images=[]
for variant in range(3):
    im=Image.new('RGBA',(S,S))
    mask=Image.new('L',im.size)
    ImageDraw.Draw(mask).rounded_rectangle((65,65,1135,1135),radius=245,fill=255)
    bg=Image.new('RGBA',im.size)
    px=bg.load()
    for y in range(S):
        for x in range(S):
            h=math.exp(-(((x-600)/340)**2+((y-600)/360)**2))
            px[x,y]=(int(9+22*h),int(9+5*h),int(19+34*h),255)
    bg.putalpha(mask)
    im=bg
    ink=Image.new('RGBA',im.size)
    d=ImageDraw.Draw(ink)
    if variant==0:
        for j,(angle,c) in enumerate(zip((-32,28,88),COLORS)):
            orbit(d,380,155,angle,(*c,190),4)
            orbit(d,392,165,angle,(*c,65),2)
        balls=[(365,415,78,COLORS[0]),(796,363,61,COLORS[2]),
               (824,740,91,COLORS[2]),(520,862,66,COLORS[1]),
               (302,660,43,COLORS[0]),(660,547,35,COLORS[1])]
    elif variant==1:
        # Closer to the reference: airy fan of trajectories and satellite clusters.
        for j in range(13):
            orbit(d,370,205,j*13-75,(*COLORS[j%3],115),2,wobble=.04,phase=j*.4)
        balls=[(323,414,81,COLORS[0]),(385,493,36,COLORS[0]),
               (297,719,68,COLORS[0]),(790,367,59,COLORS[2]),
               (863,643,92,COLORS[2]),(796,749,33,COLORS[2]),
               (529,792,64,COLORS[1]),(656,852,42,COLORS[1]),
               (578,643,31,COLORS[1])]
    else:
        # A compact sculptural constellation, crossed by a tilted orbital belt.
        for band in range(5):
            orbit(d,390+band*7,140+band*6,-28,(*COLORS[band%3],150-band*17),3)
        orbit(d,308,272,68,(*COLORS[1],95),2)
        balls=[(521,423,106,COLORS[0]),(715,520,126,COLORS[2]),
               (481,718,118,COLORS[1]),(829,369,37,COLORS[2]),
               (299,715,36,COLORS[0])]
    im=Image.alpha_composite(im,ink.filter(ImageFilter.GaussianBlur(10)))
    im=Image.alpha_composite(im,ink)
    for x,y,r,c in balls: sphere(im,x,y,r,c)
    im.putalpha(mask)
    im=im.resize((1024,1024),Image.Resampling.LANCZOS)
    im.save(DEST/f'reference-inspired-{variant+1}.png')
    images.append(im)
sheet=Image.new('RGB',(1800,665),(23,23,29))
d=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',27)
except OSError: font=ImageFont.load_default(size=27)
for i,(im,name) in enumerate(zip(images,['1. Orbital constellation','2. Spatial symphony','3. Chromatic trio'])):
    preview=im.resize((590,590),Image.Resampling.LANCZOS)
    sheet.paste(preview,(600*i+5,0),preview)
    d.text((600*i+300,620),name,font=font,fill=(237,233,245),anchor='mm')
sheet.save(DEST/'reference-inspired-candidates.jpg',quality=95)
print(DEST/'reference-inspired-candidates.jpg')
