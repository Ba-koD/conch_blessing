"""Display the exact Aseprite exports; never edit or resample source artwork."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ITEMS = [
    ("sealed_demon_sword", "봉인된 마검"),
    ("tyrfing", "티르핑"),
    ("oral_steroids", "경구형 스테로이드"),
    ("severed_oath", "적사단지"),
]
font_path = "C:/Windows/Fonts/malgun.ttf"
title = ImageFont.truetype(font_path, 26)
label = ImageFont.truetype(font_path, 18)
small = ImageFont.truetype(font_path, 14)
sheet = Image.new("RGB", (1060, 710), "#ded6c7")
draw = ImageDraw.Draw(sheet)
draw.text((24, 18), "Aseprite · 32×32 네 종 검토본", font=title, fill="#25212a")
draw.text((24, 61), "각 칸: 원본 / 수정본 / 어두운 배경 · 4배 최근접 확대와 실제 크기", font=label, fill="#665c56")
for i, (key, name) in enumerate(ITEMS):
    x = 20 + (i % 2) * 520
    y = 104 + (i // 2) * 300
    draw.rounded_rectangle((x, y, x+500, y+282), 8, fill="#f0e8d8")
    draw.text((x+16, y+12), name, font=label, fill="#25212a")
    original = Image.open(ROOT / "resources/gfx/items/collectibles" / f"{key}.png").convert("RGBA")
    revised = Image.open(HERE / f"{key}.png").convert("RGBA")
    if revised.size != (32, 32):
        raise ValueError(f"Unexpected native dimensions: {key}")
    if set(revised.getchannel("A").get_flattened_data()) != {0, 255}:
        raise ValueError(f"Unexpected antialiasing: {key}")
    for j, (sprite, caption) in enumerate(((original, "원본"), (revised, "수정본"), (revised, "어두운 배경"))):
        left = x+14+j*162
        if j == 2:
            draw.rectangle((left, y+44, left+146, y+228), fill="#302c34")
        big = sprite.resize((128,128), Image.Resampling.NEAREST)
        sheet.paste(big, (left+8,y+50), big)
        sheet.paste(sprite, (left+56,y+190), sprite)
        draw.text((left+38,y+244), caption, font=small, fill="#665c56")
sheet.save(HERE / "comparison.png")
print("Rendered four original/export comparisons at 1x and 4x.")
