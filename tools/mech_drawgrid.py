# Рисует сетку координат поверх снимков gridshot.py и склеивает три вида модели в одну картинку.
import sys, os, glob
from PIL import Image, ImageDraw

D = sys.argv[1]
for nm in sys.argv[2:]:
	views = []
	for vn in ("front", "side", "top"):
		p = os.path.join(D, "%s_%s.png" % (nm, vn))
		ch, cv, S, R = open(p + ".txt").read().split()
		ch, cv, S, R = float(ch), float(cv), float(S), int(R)
		im = Image.open(p).convert("RGB")
		dr = ImageDraw.Draw(im)
		def px(a):   # координата по горизонтали -> пиксель
			return (a - ch) / S * R + R / 2
		def py(b):   # по вертикали (вверх) -> пиксель
			return R / 2 - (b - cv) / S * R
		k0 = int((ch - S / 2) / 0.05) - 1
		k1 = int((ch + S / 2) / 0.05) + 1
		for k in range(k0, k1 + 1):
			a = k * 0.05
			x = px(a)
			major = k % 2 == 0
			dr.line([(x, 0), (x, R)], fill=(255, 60, 60) if k == 0 else ((230, 230, 0) if major else (120, 120, 120)), width=1)
			if major:
				dr.text((x + 2, 2), "%.1f" % a, fill=(255, 255, 0))
		k0 = int((cv - S / 2) / 0.05) - 1
		k1 = int((cv + S / 2) / 0.05) + 1
		for k in range(k0, k1 + 1):
			b = k * 0.05
			y = py(b)
			major = k % 2 == 0
			dr.line([(0, y), (R, y)], fill=(255, 60, 60) if k == 0 else ((230, 230, 0) if major else (120, 120, 120)), width=1)
			if major:
				dr.text((2, y + 2), "%.1f" % b, fill=(255, 255, 0))
		dr.text((R - 260, R - 20), {"front": "FRONT  right=+X up=Z", "side": "SIDE  right=+Y(back) up=Z", "top": "TOP  right=+X up=+Y(back)"}[vn], fill=(255, 255, 255))
		views.append(im)
	sheet = Image.new("RGB", (R * 3, R))
	for i, im in enumerate(views):
		sheet.paste(im, (i * R, 0))
	sheet.save(os.path.join(D, "%s_grid.png" % nm))
print("ok")
