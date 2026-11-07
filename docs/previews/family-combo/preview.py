"""Compose review layouts from the exact native PNGs; never author sprite pixels."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RUNTIME = ROOT / "resources/gfx/items/collectibles/kids_menu.png"
FONT = "C:/Windows/Fonts/malgun.ttf"
TITLE = ImageFont.truetype(FONT, 22)
LABEL = ImageFont.truetype(FONT, 16)
SMALL = ImageFont.truetype(FONT, 14)


def paste(canvas, icon, xy, scale=1):
    if scale != 1:
        icon = icon.resize((32 * scale, 32 * scale), Image.Resampling.NEAREST)
    canvas.paste(icon, xy, icon)


icon = Image.open(RUNTIME).convert("RGBA")
assert icon.size == (32, 32)
sheet = Image.new("RGB", (640, 408), "#ded6c7")
draw = ImageDraw.Draw(sheet)
draw.text((20, 14), "패밀리 세트 · 접시 안에 담긴 구도", font=TITLE, fill="#25212a")
for i, background in enumerate(("#eee3ce", "#28252d")):
    x = 12 + i * 314
    draw.rounded_rectangle((x, 59, x + 302, 371), 7, fill=background)
    paste(sheet, icon, (x + 24, 68), 8)
    paste(sheet, icon, (x + 135, 332))
draw.text((20, 381), "8배 최근접 확대 / 아래는 실제 크기", font=SMALL, fill="#665c56")
sheet.save(HERE / "preview.png")

sheet = Image.new("RGB", (760, 420), "#ded6c7")
draw = ImageDraw.Draw(sheet)
draw.text((20, 13), "패밀리 세트 · 접시와 내용물의 연결 수정", font=TITLE, fill="#25212a")
for i, (label, path) in enumerate((("이전 적용본", HERE / "previous.png"), ("접시 안쪽으로 담고 테두리 노출", RUNTIME))):
    x = 12 + i * 374
    draw.rounded_rectangle((x, 55, x + 361, 397), 8, fill="#f0e8d8")
    draw.text((x + 14, 66), label, font=LABEL, fill="#25212a")
    current = Image.open(path).convert("RGBA")
    paste(sheet, current, (x + 48, 91), 8)
    paste(sheet, current, (x + 80, 351))
    draw.rectangle((x + 200, 347, x + 240, 389), fill="#29262c")
    paste(sheet, current, (x + 204, 351))
    draw.text((x + 13, 365), "1배", font=SMALL, fill="#665c56")
sheet.save(HERE / "comparison.png")
print("Saved native-size and nearest-neighbor review layouts")
