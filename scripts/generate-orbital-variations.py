#!/usr/bin/env python3
"""Three review-only Orbital Harmony concepts. Requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

DEST=Path(__file__).resolve().parent.parent/'SpaceVisualizerApp/Resources/IconCandidates'
DEST.mkdir(parents=True,exist_ok=True)
S=1600
colors=[(175,112,255),(100,239,207),(255,169,102)]
images=[]
for variant in range(3):
    im=Image.new('RGBA',(S,S))
    ImageDraw.Draw(im).rounded_rectangle((90,90,1510,1510),radius=322,fill=(13,11,28),outline=(48,39,70),width=3)
    ink=Image.new('RGBA',im.size)
    d=ImageDraw.Draw(ink)
    if variant==0:
        # Three sweeping orbital ribbons with quiet, deliberately open ends.
        for j,angle in enumerate((-32,28,88)):
            a=math.radians(angle)
            for band in range(4):
                pts=[]
                for step in range(801):
                    t=math.radians(-145+step*315/800+j*32)
                    x=(488-band*13)*math.cos(t)
                    y=(205-band*9)*math.sin(t)
                    pts.append((800+x*math.cos(a)-y*math.sin(a),800+x*math.sin(a)+y*math.cos(a)))
                for k in range(len(pts)-1):
                    fade=math.sin(math.pi*(k+.5)/(len(pts)-1))**.45
                    d.line(pts[k:k+2],fill=(*colors[j],int((245-band*38)*fade)),width=10 if band==0 else 4)
    elif variant==1:
        # Interwoven orbits with depth-sorted luminous front faces.
        segments=[]
        for j,angle in enumerate((-34,26,86)):
            a=math.radians(angle)
            for band in range(2):
                pts=[]
                for step in range(721):
                    t=step*math.pi/360
                    x=(490-band*24)*math.cos(t)
                    y=(215-band*12)*math.sin(t)
                    pts.append((800+x*math.cos(a)-y*math.sin(a),800+x*math.sin(a)+y*math.cos(a)))
                for k in range(720):
                    z=math.sin(k*math.pi/360)
                    c=tuple(int(v*(.42+.58*(z+1)/2)) for v in colors[j])
                    segments.append((z,pts[k:k+2],(*c,255),18 if band==0 else 4))
        for z,pts,c,w in sorted(segments,key=lambda s:s[0]):
            d.line(pts,fill=(13,11,28,255),width=w+9)
            d.line(pts,fill=c,width=w)
    else:
        # A subtle three-dimensional audio pulse flowing through each orbit.
        for j,angle in enumerate((-35,25,85)):
            a=math.radians(angle)
            for band in range(3):
                pts=[]
                for step in range(1441):
                    t=step*math.pi/720
                    pulse=math.exp(-(math.atan2(math.sin(t-.8-j*.45),math.cos(t-.8-j*.45))/.46)**2)
                    modulation=36*pulse*math.sin(t*18+j*.8)
                    x=(480-band*16+modulation)*math.cos(t)
                    y=(208-band*10+modulation*.75)*math.sin(t)
                    pts.append((800+x*math.cos(a)-y*math.sin(a),800+x*math.sin(a)+y*math.cos(a)))
                d.line(pts,fill=(*colors[j],245-band*58),width=9 if band==0 else 4,joint='curve')
    im=Image.alpha_composite(im,ink.filter(ImageFilter.GaussianBlur(19)))
    im=Image.alpha_composite(im,ink)
    im=im.resize((1024,1024),Image.Resampling.LANCZOS)
    im.save(DEST/f'orbital-creative-{variant+1}.png')
    images.append(im)
sheet=Image.new('RGB',(1800,665),(23,23,29))
d=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',27)
except OSError: font=ImageFont.load_default(size=27)
for i,(im,name) in enumerate(zip(images,['1. Celestial ribbons','2. Interstellar weave','3. Resonant orbits'])):
    preview=im.resize((590,590),Image.Resampling.LANCZOS)
    sheet.paste(preview,(i*600+5,0),preview)
    d.text((i*600+300,620),name,font=font,fill=(237,233,245),anchor='mm')
sheet.save(DEST/'orbital-three-versions.jpg',quality=95)
print(DEST/'orbital-three-versions.jpg')
