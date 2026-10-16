# Складывает кадры из tools/render_flipbook.py в лист по 8 в ряд (32 кадра — 8×4, 64 — 8×8; PNG с прозрачностью):
#   python tools/pack_flipbook.py <папка_кадров> <файл.png> [размер_кадра]
import os, sys
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
cell = int(sys.argv[3]) if len(sys.argv) > 3 else 256
frames = sorted(f for f in os.listdir(src) if f.startswith("f") and f.endswith(".png"))[:64]
rows = (len(frames) + 7) // 8
sheet = Image.new("RGBA", (cell * 8, cell * rows), (0, 0, 0, 0))
for i, f in enumerate(frames):
    im = Image.open(os.path.join(src, f)).convert("RGBA").resize((cell, cell), Image.LANCZOS)
    sheet.paste(im, ((i % 8) * cell, (i // 8) * cell))
sheet.save(dst, optimize=True)
print("лист", dst, len(frames), "кадров")
