#!/usr/bin/env python3
# 生成 dsh App 图标 (1024x1024) 终端/提示符 motif
from PIL import Image, ImageDraw, ImageFilter
import math

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
px = img.load()

# 背景：深蓝竖向渐变（iOS 圆角由系统裁切，这里画个略小于全幅的圆角方块）
top = (11, 18, 32)
bot = (15, 32, 65)
for y in range(S):
    t = y / S
    r = int(top[0] + (bot[0]-top[0])*t)
    g = int(top[1] + (bot[1]-top[1])*t)
    b = int(top[2] + (bot[2]-top[2])*t)
    for x in range(S):
        px[x, y] = (r, g, b, 255)

# 圆角遮罩
mask = Image.new("L", (S, S), 0)
md = ImageDraw.Draw(mask)
rad = 230
md.rounded_rectangle([0,0,S-1,S-1], radius=rad, fill=255)
img.putalpha(mask)

# 终端窗口：圆角矩形框，内圈描边
d = ImageDraw.Draw(img)
pad = 190
tw = S - pad*2
tw_top = 340
tw_h = 470
box = [pad, tw_top, pad+tw, tw_top+tw_h]
d.rounded_rectangle(box, radius=48, outline=(120,220,255,80), width=14)

# 窗口标题栏三个点
for i, col in enumerate([(255,95,86),(255,189,46),(39,201,63)]):
    cx = pad + 70 + i*92
    cy = tw_top + 62
    d.ellipse([cx-26, cy-26, cx+26, cy+26], fill=col+(255,))

# 提示符 "❯" 用粗线段组合 + 光标下划线
# 提示符箭头
acx = pad + 120
acy = tw_top + 250
lw = 34
d.line([(acx,acy),(acx+86,acy+64)], fill=(0,230,180,255), width=lw)
d.line([(acx,acy+128),(acx+86,acy+64)], fill=(0,230,180,255), width=lw)

# 光标方块
cur_x0 = pad + 250
cur_y0 = tw_top + 196
d.rounded_rectangle([cur_x0,cur_y0,cur_x0+150,cur_y0+150], radius=26, fill=(0,230,180,255))

# 底部状态条
d.rounded_rectangle([pad, S-pad-95, pad+tw, S-pad-28], radius=30, outline=(120,160,255,90), width=10)

img = img.resize((S,S), Image.LANCZOS)
img.save("/var/minis/workspace/dsh-ios/DashHarness/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
print("icon written, size", img.size)