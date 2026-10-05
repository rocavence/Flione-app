# 產生 app icon：漸層 F（scripts/icon/flione-f-gradient.png，由原圖依幾何重繪、修掉藍橘交接處的鋸齒）放在 macOS 格線的白色圓角方形上。
# 用法：python3 scripts/icon/compose-icon.py <輸出 1024px PNG>，再縮成 AppIcon.appiconset 的各尺寸

import numpy as np, sys
from PIL import Image, ImageFilter
S=4; N=1024*S
f=Image.open("scripts/icon/flione-f-gradient.png").convert("RGBA"); f=f.crop(f.getbbox())
def rounded(size, radius):
    # macOS 圓角方形：連續曲率的圓角，用超橢圓角（n=2.6）近似 Apple 的平滑圓角
    c=np.arange(size)+0.5
    x=np.minimum(c, size-c); xx,yy=np.meshgrid(x,x)
    dx=np.clip(radius-xx,0,None)/radius; dy=np.clip(radius-yy,0,None)/radius
    return ((dx**2.6+dy**2.6)<=1).astype(np.float32)
def make(bg, shadow_alpha):
    side=824*S; off=(N-side)//2
    m=rounded(side, 185*S*1.28)
    canvas=Image.new("RGBA",(N,N),(0,0,0,0))
    sh=Image.new("L",(N,N),0); sh.paste(Image.fromarray((m*255*shadow_alpha).astype(np.uint8)),(off,off+10*S))
    sh=sh.filter(ImageFilter.GaussianBlur(14*S))
    canvas.paste(Image.new("RGBA",(N,N),(0,0,0,255)),(0,0),sh)
    body=Image.new("RGBA",(side,side),bg+(255,))
    h=int(side*0.64); w=int(f.width*h/f.height)
    body.alpha_composite(f.resize((w,h),Image.LANCZOS),((side-w)//2+int(side*0.015),(side-h)//2))
    canvas.paste(body,(off,off),Image.fromarray((m*255).astype(np.uint8)))
    return canvas.resize((1024,1024),Image.LANCZOS)
# 底色 #FAF6F0（接近白色的暖米色）
make((0xFA,0xF6,0xF0),0.30).save(sys.argv[1] if len(sys.argv) > 1 else "appicon.png")

