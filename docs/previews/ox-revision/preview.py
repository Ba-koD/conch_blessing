"""Build the directional ANM2 from the current runtime contract and display it.

Only the draft ANM2, comparison PNG and animated GIF are written here.
Artwork is authored at native resolution by Aseprite/directions.lua.
"""
from pathlib import Path
from copy import deepcopy
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RUNTIME = ROOT / "resources/gfx/effects"
FONT = "C:/Windows/Fonts/malgun.ttf"
TITLE = ImageFont.truetype(FONT, 25)
LABEL = ImageFont.truetype(FONT, 18)
SMALL = ImageFont.truetype(FONT, 14)


def build_animation():
    tree = ET.parse(RUNTIME / "conch_ox.anm2")
    root = tree.getroot()
    root.find('./Content/Spritesheets/Spritesheet[@Id="0"]').set("Path", "conch_ox_directions.png")
    root.find('./Content/Spritesheets/Spritesheet[@Id="1"]').set("Path", "conch_ox_sleep_equipped.png")
    animations = root.find("Animations")
    def update(anim, color, direction):
        row = (0 if color == "Yellow" else 3) + direction
        for f in anim.findall('./LayerAnimations/LayerAnimation[@LayerId="0"]/Frame'):
            old_width = int(f.get("Width"))
            index = int(f.get("XCrop")) // old_width
            for key, value in {"XCrop": index*80, "YCrop": row*80,
                               "Width": 80, "Height": 80, "XPivot": 48, "YPivot": 48}.items():
                f.set(key, str(value))
    for color in ("Yellow", "Black"):
        for pose in ("Walk", "Idle"):
            original = animations.find(f'Animation[@Name="{color}{pose}"]')
            update(original, color, 0)
            for direction, suffix in ((1, "Down"), (2, "Up")):
                name = color+pose+suffix
                prior = animations.find(f'Animation[@Name="{name}"]')
                if prior is not None:
                    animations.remove(prior)
                added = deepcopy(original)
                added.set("Name", name)
                update(added, color, direction)
                animations.append(added)
        sleep = animations.find(f'Animation[@Name="{color}Sleep"]')
        for frame in sleep.findall('./LayerAnimations/LayerAnimation[@LayerId="1"]/Frame'):
            index = int(frame.get("XCrop")) // int(frame.get("Width"))
            for key, value in {"XCrop": index*80, "YCrop": (0 if color == "Yellow" else 80),
                               "Width": 80, "Height": 80, "XPivot": 48, "YPivot": 48}.items():
                frame.set(key, str(value))
    ET.indent(tree, space="  ")
    tree.write(HERE / "conch_ox.anm2", encoding="utf-8", xml_declaration=False)
    return root


ANM2 = build_animation()
SHEETS = {}
for entry in ANM2.findall("./Content/Spritesheets/Spritesheet"):
    path = HERE / entry.get("Path")
    if not path.exists():
        path = RUNTIME / entry.get("Path")
    SHEETS[entry.get("Id")] = Image.open(path).convert("RGBA")
LAYERS = {entry.get("Id"): entry.get("SpritesheetId") for entry in ANM2.findall("./Content/Layers/Layer")}


def render(name, tick=0, flip=False):
    anim = ANM2.find(f'./Animations/Animation[@Name="{name}"]')
    local = tick % int(anim.get("FrameNum"))
    canvas = Image.new("RGBA", (80, 80))
    for track in anim.findall("./LayerAnimations/LayerAnimation"):
        if track.get("Visible") == "false":
            continue
        elapsed = 0
        for frame in track.findall("Frame"):
            elapsed += int(frame.get("Delay"))
            if local >= elapsed:
                continue
            if frame.get("Visible") != "false":
                sheet = SHEETS[LAYERS[track.get("LayerId")]]
                x, y, w, h = [int(frame.get(k)) for k in ("XCrop", "YCrop", "Width", "Height")]
                image = sheet.crop((x, y, x+w, y+h))
                offset = (48-int(frame.get("XPivot")), 48-int(frame.get("YPivot")))
                canvas.alpha_composite(image, offset)
            break
    if flip:
        canvas = canvas.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return canvas


def paste(canvas, source, x, y, scale=1):
    if scale != 1:
        source = source.resize((source.width*scale, source.height*scale), Image.Resampling.NEAREST)
    canvas.paste(source, (x, y), source)


VIEWS = [("", True, "← 왼쪽"), ("Up", False, "↑ 위쪽 / 뒷모습"),
         ("Down", False, "↓ 아래쪽 / 앞모습"), ("", False, "→ 오른쪽")]
COLORS = [("Yellow", "누렁소"), ("Black", "검은소")]
sheet = Image.new("RGB", (1080, 1220), "#ded6c7")
d = ImageDraw.Draw(sheet)
d.text((22, 18), "OX · 상하좌우 보행과 쟁기", font=TITLE, fill="#25212a")
d.text((22, 57), "위·아래 쟁기 길이 조정 · 수면 시 멍에와 끈 유지", font=LABEL, fill="#665c56")
for row, (color, label) in enumerate(COLORS):
    for col, (suffix, flip, caption) in enumerate(VIEWS):
        x = 12+col*267
        y = 100+row*394
        d.rounded_rectangle((x, y, x+255, y+380), 7, fill="#f0e8d8")
        d.text((x+12, y+12), label+" · "+caption, font=LABEL, fill="#25212a")
        pose = render(color+"Idle"+suffix, flip=flip)
        paste(sheet, pose, x+6, y+44, 3)
        paste(sheet, pose, x+48, y+293)
        d.rectangle((x+146, y+292, x+240, y+378), fill="#302c34")
        paste(sheet, pose, x+153, y+295)
for col, (color, label) in enumerate(COLORS):
    x = 12+col*534
    y = 902
    d.rounded_rectangle((x, y, x+522, y+270), 7, fill="#f0e8d8")
    d.text((x+15, y+12), label+" · 멍에를 착용한 수면 자세", font=LABEL, fill="#25212a")
    pose = render(color+"Sleep")
    paste(sheet, pose, x+12, y+36, 3)
    paste(sheet, pose, x+291, y+104)
    d.text((x+295, y+195), "뒤에 끄는 쟁기 생략", font=SMALL, fill="#665c56")
d.text((22, 1193), "검토본 · 본체는 원본 픽셀 유지 · 확대는 최근접 방식 · 게임에는 아직 적용하지 않음", font=SMALL, fill="#665c56")
sheet.save(HERE / "comparison.png")

# Read durations from the ANM2 rather than giving a GIF independent timing.
walk = ANM2.find('./Animations/Animation[@Name="YellowWalk"]')
entries = walk.findall('./LayerAnimations/LayerAnimation[@LayerId="0"]/Frame')
boundaries = [0]
for frame in entries:
    boundaries.append(boundaries[-1]+int(frame.get("Delay")))
frames, durations = [], []
for start, end in zip(boundaries, boundaries[1:]):
    canvas = Image.new("RGB", (1080, 710), "#ded6c7")
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 14), "OX · 상하좌우 걷기 + 쟁기", font=TITLE, fill="#25212a")
    for row, (color, label) in enumerate(COLORS):
        for col, (suffix, flip, caption) in enumerate(VIEWS):
            x = 12+col*267
            y = 65+row*307
            draw.rounded_rectangle((x, y, x+255, y+295), 7, fill="#f0e8d8")
            draw.text((x+10, y+10), label+" · "+caption, font=LABEL, fill="#25212a")
            pose = render(color+"Walk"+suffix, start, flip)
            paste(canvas, pose, x+6, y+42, 3)
    frames.append(canvas)
    durations.append(round(end*100/30)*10-round(start*100/30)*10)
frames[0].save(HERE / "walk.gif", save_all=True, append_images=frames[1:],
               duration=durations, loop=0, disposal=2)

sleep_frames = []
for tick in (0, 15, 30, 45):
    canvas = Image.new("RGB", (800, 340), "#ded6c7")
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 14), "OX · 멍에를 착용한 수면 자세", font=TITLE, fill="#25212a")
    for col, (color, label) in enumerate(COLORS):
        x = 12+col*394
        draw.rounded_rectangle((x, 57, x+382, 324), 7, fill="#f0e8d8")
        draw.text((x+14, 69), label+" · 멍에와 끈만 유지", font=LABEL, fill="#25212a")
        paste(canvas, render(color+"Sleep", tick), x+23, 99, 3)
        paste(canvas, render(color+"Sleep", tick), x+282, 170)
    sleep_frames.append(canvas)
sleep_frames[0].save(HERE / "sleep.gif", save_all=True, append_images=sleep_frames[1:],
                     duration=500, loop=0, disposal=2)
print("Saved directional/sleep ANM2, full overview, walk GIF and equipped sleep GIF.")
