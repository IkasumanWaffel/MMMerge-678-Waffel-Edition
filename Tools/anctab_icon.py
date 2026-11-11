"""anctab_icon.py - the Ancient memory tablet icon (11.11.26), drawn from scratch:
an orange rugged frame with chamfered corners around a black screen with a faint orange grid
and an orange hexagon, a cyan status light on top. Drawn at 8x and scaled down.

    python Tools/anctab_icon.py <out.png preview> -> returns the icons.lod blob via make()
"""
import math, numpy as np
from PIL import Image, ImageDraw, ImageFilter
import artifact_icons as ai

W, H, K = 44, 60, 8

def chamfer(x0, y0, x1, y1, c):
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]

def draw():
    w, h = W * K, H * K
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # body: dark rim, orange frame, lighter bevel
    d.polygon(chamfer(4, 4, w - 5, h - 5, 40), fill=(70, 30, 6, 255))
    d.polygon(chamfer(12, 12, w - 13, h - 13, 34), fill=(232, 120, 22, 255))
    d.polygon(chamfer(22, 22, w - 23, h - 23, 28), fill=(250, 150, 40, 255))
    # side grips
    for y in (h * 0.30, h * 0.52):
        d.rectangle([0, y, 14, y + 34], fill=(40, 20, 6, 255))
        d.rectangle([w - 15, y, w - 1, y + 34], fill=(40, 20, 6, 255))
    # bottom bezel
    d.polygon([(w * 0.30, h - 58), (w * 0.70, h - 58), (w * 0.64, h - 30), (w * 0.36, h - 30)], fill=(200, 96, 16, 255))
    # screen
    sx0, sy0, sx1, sy1 = 44, 52, w - 45, h - 72
    d.polygon(chamfer(sx0 - 6, sy0 - 6, sx1 + 6, sy1 + 6, 16), fill=(30, 14, 4, 255))
    d.rectangle([sx0, sy0, sx1, sy1], fill=(8, 6, 6, 255))
    step = 24
    for x in range(sx0 + step, sx1, step):
        d.line([x, sy0, x, sy1], fill=(70, 30, 10, 255), width=2)
    for y in range(sy0 + step, sy1, step):
        d.line([sx0, y, sx1, y], fill=(70, 30, 10, 255), width=2)
    # hexagon (pointy top), glow then line
    cx, cy = (sx0 + sx1) / 2, (sy0 + sy1) / 2
    rx, ry = (sx1 - sx0) * 0.36, (sy1 - sy0) * 0.36
    pts = [(cx + rx * math.sin(math.radians(a)), cy - ry * math.cos(math.radians(a))) for a in range(0, 360, 60)]
    glow = Image.new('RGBA', im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).line(pts + [pts[0]], fill=(255, 90, 20, 200), width=30, joint='curve')
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10)))
    d = ImageDraw.Draw(im)
    d.line(pts + [pts[0]], fill=(255, 110, 30, 255), width=14, joint='curve')
    # the text band in the middle
    d.rectangle([sx0 + 10, cy - 18, sx1 - 10, cy + 18], fill=(90, 26, 8, 255))
    d.rectangle([cx - rx * 0.55, cy - 9, cx + rx * 0.55, cy + 9], fill=(255, 120, 40, 255))
    # status light on top
    d.polygon([(w * 0.36, 14), (w * 0.64, 14), (w * 0.60, 26), (w * 0.40, 26)], fill=(80, 240, 240, 255))
    return im

def make(name='anctab'):
    big = draw()
    return ai.to_icon(big, (W, H), name, sharpen=True)

if __name__ == '__main__':
    import sys
    b = make()
    ai.preview(b, 6).save(sys.argv[1])
    draw().save(sys.argv[1].replace('.png', '_big.png'))
