"""Renders 장승 as real 3D posts in the room's own projection (user request
2026-11-10: "build the map's view in 3D, set our 장승 in it and work from that").

The room backdrop is drawn as a box seen from straight above its middle: the
floor far below, the walls leaning outward to their rims, every door turned to
face its wall. This script reproduces that with a pinhole camera above the
room's centre (world (320, 280), looking straight down), whose floor scale is
the game's 26 px per 40 units and whose height puts the wall rims where the
basement backdrop draws them. Each statue is a box post standing against its
wall beside the door, facing into the room, its four sides textured with the
front, side and back art and its top dark like the cap; the faces are drawn
far to near with perspective-correct (homography) sampling. The backdrop,
doors and earth come from placement.py, read in place from extracted_resources.

    python docs/previews/jangseung/scene3d.py [camera height]
"""
import importlib.util
import sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / '.tmp/jangseung'


def load(name, rel):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    saved = sys.argv
    sys.argv = [saved[0]]
    spec.loader.exec_module(module)
    sys.argv = saved
    return module


author = load('author', 'docs/previews/jangseung/author.py')
placement = load('placement', 'docs/previews/jangseung/placement.py')

SCALE = 26 / 40          # floor pixels per world unit
CENTER = (320.0, 280.0)  # the room's middle, under the camera
IMG_CENTER = (234.0, 156.0)


class Camera:
    def __init__(self, height):
        self.h = height
        self.f = SCALE * height  # so the floor (z = 0) keeps the game's scale

    def project(self, x, y, z):
        d = self.h - z
        return (IMG_CENTER[0] + self.f * (x - CENTER[0]) / d, IMG_CENTER[1] + self.f * (y - CENTER[1]) / d)

    def position(self):
        return np.array([CENTER[0], CENTER[1], self.h])


def homography(src, dst):
    """3x3 H with dst ~ H @ src for four point pairs."""
    rows = []
    for (x, y), (u, v) in zip(src, dst):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y, -u])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y, -v])
    _, _, vt = np.linalg.svd(np.array(rows, dtype=float))
    return vt[-1].reshape(3, 3)


def draw_quad(canvas, camera, corners, texture):
    """Draws `texture` on the 3D quad `corners` (top-left, top-right,
    bottom-right, bottom-left as seen from outside), nearest texel."""
    screen = [camera.project(*c) for c in corners]
    tw, th = texture.size
    uv = [(0, 0), (tw, 0), (tw, th), (0, th)]
    inv = homography(screen, uv)
    xs, ys = [p[0] for p in screen], [p[1] for p in screen]
    x0, x1 = int(np.floor(min(xs))), int(np.ceil(max(xs)))
    y0, y1 = int(np.floor(min(ys))), int(np.ceil(max(ys)))
    px = texture.load()
    out = canvas.load()
    for y in range(max(0, y0), min(canvas.height, y1 + 1)):
        for x in range(max(0, x0), min(canvas.width, x1 + 1)):
            u, v, w = inv @ np.array([x + 0.5, y + 0.5, 1.0])
            if w == 0:
                continue
            u, v = u / w, v / w
            if 0 <= u < tw and 0 <= v < th:
                c = px[int(u), int(v)]
                if c[3] > 0:
                    out[x, y] = c


def statue_faces(cx, cy, nx, ny, width, depth, height, textures):
    """The visible-candidate faces of a post at (cx, cy) facing (nx, ny):
    (centre, normal, corners, texture)."""
    n = np.array([nx, ny, 0.0])
    r = np.array([ny, -nx, 0.0])  # the right hand of someone looking at its front
    c = np.array([cx, cy, 0.0])
    up = np.array([0, 0, height])
    w2, d2 = width / 2, depth / 2

    def quad(origin, right, tex):
        tl, tr = origin - right + up, origin + right + up
        return [tl, tr, origin + right, origin - right], tex

    faces = []
    front = c + n * d2
    faces.append((front + up / 2, n) + quad(front, r * w2, textures['front']))
    back = c - n * d2
    faces.append((back + up / 2, -n) + quad(back, -r * w2, textures['back']))
    # its left side (towards +r): the face looks to the viewer's left
    left = c + r * w2
    faces.append((left + up / 2, r) + quad(left, n * d2, textures['side'].transpose(Image.FLIP_LEFT_RIGHT)))
    right_side = c - r * w2
    faces.append((right_side + up / 2, -r) + quad(right_side, -n * d2, textures['side']))
    top_c = c + up
    tl = top_c - r * w2 + n * d2 * -1
    faces.append((top_c, np.array([0, 0, 1.0]),
                  [c + up - r * w2 - n * d2, c + up + r * w2 - n * d2, c + up + r * w2 + n * d2, c + up - r * w2 + n * d2],
                  textures['top']))
    return faces


def textures_for(who):
    """The standing statue's front art, a bare post on its sides and back, and
    its cap or hair seen from above on its top."""
    front = author.statue('Upright', who)
    post = author.plain_post(front.width, front.height)
    return {'front': front, 'side': post, 'back': post, 'top': top_view(who)}


def top_view(who):
    """The post's top seen from above (18x18, u along its width, v toward its
    front): the round head's wood, under 천하대장군's cap with its wings
    straight out to the sides, or 지하여장군's hair and topknot."""
    p = author.PALETTE
    img = Image.new('RGBA', (18, 18))
    for y in range(18):
        for x in range(18):
            d = ((x - 8.5) ** 2 + (y - 8.5) ** 2) ** 0.5
            if d <= 8.6:
                img.putpixel((x, y), p['K'] if d > 7.6 else p['L'] if x + y < 15 else p['M'])
    for y in range(18):
        for x in range(18):
            d = ((x - 8.5) ** 2 + (y - 8.5) ** 2) ** 0.5
            if who == 'Cheonha':
                wing = 7 <= y <= 9
                if d <= 5.6 or wing:
                    edge = d > 4.6 and not wing or wing and y != 8
                    img.putpixel((x, y), p['K'] if edge else p['h'] if x < 8 and y < 8 else p['H'])
            else:
                if d <= 7.2:
                    img.putpixel((x, y), p['K'] if d > 6.4 else p['H'])
                if d <= 2.4:
                    img.putpixel((x, y), p['K'] if d > 1.6 else p['h'])
    return img


def render(height, spread=46, inset=14, size=(28, 28, 62)):
    room = placement.backdrop()
    door = placement.door_sprite()
    earth = Image.open(ROOT / 'resources/gfx/effects/conch_jangseung_ground.png').convert('RGBA')
    camera = Camera(height)
    tex = {'Cheonha': textures_for('Cheonha'), 'Jiha': textures_for('Jiha')}
    width, depth, tall = size
    posts = []
    for (wx, wy), (ix, iy), turn in placement.DOORS.values():
        placement.place(room, earth, wx, wy, (52, 0), np.degrees(np.arctan2(iy, ix)) - 90)
        placement.place(room, door, wx, wy, (32, 42), turn)
        # the floor edge in front of this wall, and the post's back against it
        edge = (wx + ix * 20, wy + iy * 20)
        sx, sy = -iy, ix
        cx, cy = edge[0] + ix * (inset + depth / 2 - 14), edge[1] + iy * (inset + depth / 2 - 14)
        a = (cx + sx * spread, cy + sy * spread)
        b = (cx - sx * spread, cy - sy * spread)
        first = a[0] < b[0] if iy != 0 else a[1] < b[1]
        for who, (x, y) in zip(('Cheonha', 'Jiha'), (a, b) if first else (b, a)):
            posts.append((x, y, ix, iy, who))
    cam = camera.position()
    faces = []
    for x, y, nx, ny, who in posts:
        for centre, normal, corners, t in statue_faces(x, y, nx, ny, width, depth, tall, tex[who]):
            if np.dot(normal, cam - centre) > 0:
                faces.append((np.linalg.norm(cam - centre), corners, t))
    for _, corners, t in sorted(faces, key=lambda f: -f[0]):
        draw_quad(room, camera, corners, t)
    return room


def main():
    heights = [float(a) for a in sys.argv[1:]] or [200.0, 320.0, 600.0]
    OUT.mkdir(parents=True, exist_ok=True)
    for h in heights:
        img = render(h)
        big = img.resize((img.width * 3, img.height * 3), Image.NEAREST)
        path = OUT / f'scene3d_h{int(h)}.png'
        big.save(path)
        print(path)


if __name__ == '__main__':
    main()
