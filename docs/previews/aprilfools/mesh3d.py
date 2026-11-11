"""A small 3D toolkit for the April Fools set: real meshes, a lit renderer and
a glTF (.glb) exporter.

Every item of the set is modelled as actual geometry (spheres, tubes swept
along paths, extruded outlines, lathed profiles...), not as its 2D sprite
pasted onto a box, so it can be turned and rendered from any side (user
request 2026-11-11). The game cannot draw a mesh, so the April Fools icons are
rendered from these models and brought down to the 32x32 grid; the .glb files
are the models themselves, for any 3D viewer.

World axes: x right, y away from the viewer, z up. glTF is y-up, so the
exporter turns (x, y, z) into (x, z, -y).
"""
import json
import math
import struct

import numpy as np
from PIL import Image


# ---------------------------------------------------------------- geometry
class Part:
    """One mesh piece with one material. `smooth` parts interpolate vertex
    normals (spheres, tubes); flat parts keep each face's own normal."""

    def __init__(self, verts, faces, mat, smooth=True, normals=None):
        self.v = np.asarray(verts, dtype=float).reshape(-1, 3)
        self.f = np.asarray(faces, dtype=np.int64).reshape(-1, 3)
        self.mat = mat
        self.smooth = smooth
        self.normals = None if normals is None else np.asarray(normals,dtype=float)

    def moved(self, matrix):
        m = np.asarray(matrix, dtype=float)
        v = self.v @ m[:3, :3].T + m[:3, 3]
        faces = self.f if np.linalg.det(m[:3, :3]) >= 0 else self.f[:, ::-1]
        normals = None
        if self.normals is not None:
            normals = self.normals @ np.linalg.inv(m[:3,:3])
            normals /= np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)
        return Part(v, faces, self.mat, self.smooth, normals)

    def vertex_normals(self):
        if self.normals is not None:
            return self.normals
        n = np.zeros_like(self.v)
        tri = self.v[self.f]
        fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        for k in range(3):
            np.add.at(n, self.f[:, k], fn)
        length = np.linalg.norm(n, axis=1, keepdims=True)
        length[length == 0] = 1
        return n / length


def move(parts, matrix):
    return [p.moved(matrix) for p in parts]


def T(x=0.0, y=0.0, z=0.0):
    m = np.eye(4)
    m[:3, 3] = (x, y, z)
    return m


def S(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    return np.diag([x, y, z, 1.0])


def R(axis, degrees):
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    m = np.eye(4)
    if axis == 'x':
        m[1:3, 1:3] = [[c, -s], [s, c]]
    elif axis == 'y':
        m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, s, -s, c
    else:
        m[0:2, 0:2] = [[c, -s], [s, c]]
    return m


def chain(*matrices):
    out = np.eye(4)
    for m in matrices:
        out = out @ m
    return out


def sphere(r, mat, seg=40, rings=20, center=(0, 0, 0), squash=(1, 1, 1)):
    verts, faces = [], []
    for i in range(rings + 1):
        th = math.pi * i / rings
        for j in range(seg):
            ph = 2 * math.pi * j / seg
            verts.append((center[0] + r * squash[0] * math.sin(th) * math.cos(ph),
                          center[1] + r * squash[1] * math.sin(th) * math.sin(ph),
                          center[2] + r * squash[2] * math.cos(th)))
    for i in range(rings):
        for j in range(seg):
            a, b = i * seg + j, i * seg + (j + 1) % seg
            c, d = a + seg, b + seg
            if i > 0:
                faces.append((a, c, b))
            if i < rings - 1:
                faces.append((b, c, d))
    return Part(verts, faces, mat, True)


def _frames(path, closed):
    """Parallel-transport frames along a path, so a swept tube never twists."""
    n = len(path)
    tangents = []
    for i in range(n):
        if closed:
            t = path[(i + 1) % n] - path[i - 1]
        else:
            t = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
        tangents.append(t / (np.linalg.norm(t) or 1))
    t0 = tangents[0]
    helper = np.array([0, 0, 1.0]) if abs(t0[2]) < 0.9 else np.array([1.0, 0, 0])
    normal = np.cross(t0, helper)
    normal /= np.linalg.norm(normal)
    normals = [normal]
    for i in range(1, n):
        prev, cur = tangents[i - 1], tangents[i]
        axis = np.cross(prev, cur)
        s = np.linalg.norm(axis)
        nm = normals[-1]
        if s > 1e-9:
            axis /= s
            ang = math.atan2(s, float(np.dot(prev, cur)))
            nm = (nm * math.cos(ang) + np.cross(axis, nm) * math.sin(ang)
                  + axis * np.dot(axis, nm) * (1 - math.cos(ang)))
        normals.append(nm / np.linalg.norm(nm))
    return tangents, normals


def sweep(path, radius, mat, seg=14, closed=False, caps=True, profile=None):
    """A tube along `path`; `radius` is a number or one per point. `profile`
    (optional) squashes the cross-section: (width, height) factors."""
    path = [np.asarray(p, dtype=float) for p in path]
    radii = radius if isinstance(radius, (list, tuple, np.ndarray)) else [radius] * len(path)
    tangents, normals = _frames(path, closed)
    sx, sy = profile or (1.0, 1.0)
    verts, faces = [], []
    for p, t, nm, r in zip(path, tangents, normals, radii):
        bn = np.cross(t, nm)
        for j in range(seg):
            a = 2 * math.pi * j / seg
            verts.append(p + r * (sx * math.cos(a) * nm + sy * math.sin(a) * bn))
    n = len(path)
    rows = n if closed else n - 1
    for i in range(rows):
        for j in range(seg):
            a = i * seg + j
            b = i * seg + (j + 1) % seg
            c = ((i + 1) % n) * seg + j
            d = ((i + 1) % n) * seg + (j + 1) % seg
            faces += [(a, b, c), (b, d, c)]
    parts = [Part(verts, faces, mat, True)]
    if caps and not closed:
        for idx, flip in ((0, True), (n - 1, False)):
            ring = list(range(idx * seg, idx * seg + seg))
            centre = len(verts)
            cv = [tuple(v) for v in verts] + [tuple(path[idx])]
            cf = [(centre, ring[(j + 1) % seg], ring[j]) if flip else (centre, ring[j], ring[(j + 1) % seg])
                  for j in range(seg)]
            parts.append(Part(cv, cf, mat, False))
    return parts


def cylinder(r, h, mat, seg=24, caps=True):
    return sweep([(0, 0, 0), (0, 0, h)], r, mat, seg=seg, caps=caps)


def lathe(profile, mat, seg=40):
    """Turn a (radius, z) profile about the z axis."""
    verts, faces = [], []
    for r, z in profile:
        for j in range(seg):
            a = 2 * math.pi * j / seg
            verts.append((r * math.cos(a), r * math.sin(a), z))
    for i in range(len(profile) - 1):
        for j in range(seg):
            a, b = i * seg + j, i * seg + (j + 1) % seg
            c, d = a + seg, b + seg
            faces += [(a, b, c), (b, d, c)]
    return [Part(verts, faces, mat, True)]


def _ear_clip(poly):
    pts = [tuple(p) for p in poly]
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
               for i in range(len(pts)))
    idx = list(range(len(pts)))
    if area < 0:
        idx.reverse()
    tris = []

    def inside(p, a, b, c):
        def s(p1, p2, p3):
            return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
        d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            a, b, c = pts[i0], pts[i1], pts[i2]
            if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                continue
            if any(inside(pts[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                continue
            tris.append((i0, i1, i2))
            idx.pop(k)
            break
        else:
            break
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def extrude(poly, depth, mat, side_mat=None, bevel=0.0):
    """A flat outline (x, z pairs, in the picture plane) given thickness along
    y, centred on y = 0. `bevel` pulls the faces in a little and rounds the
    rim with one chamfer step."""
    poly = [tuple(p) for p in poly]
    if _signed(poly)<0:poly.reverse()
    n = len(poly)
    tris = _ear_clip(poly)
    half = depth / 2

    def inset(amount):
        if amount <= 0:
            return poly
        out = []
        for i in range(n):
            p0, p1, p2 = np.array(poly[i - 1]), np.array(poly[i]), np.array(poly[(i + 1) % n])
            e1 = (p1 - p0) / (np.linalg.norm(p1 - p0) or 1)
            e2 = (p2 - p1) / (np.linalg.norm(p2 - p1) or 1)
            n1, n2 = np.array([-e1[1], e1[0]]), np.array([-e2[1], e2[0]])
            nm = n1 + n2
            nm = nm / (np.linalg.norm(nm) or 1)
            out.append(tuple(p1 + nm * amount * (1 if _signed(poly) > 0 else -1)))
        return out

    face = inset(bevel)
    verts, faces = [], []
    for (x, z) in face:
        verts.append((x, -half, z))
    for (x, z) in face:
        verts.append((x, half, z))
    for a, b, c in tris:
        faces.append((a, b, c) if _signed(poly) > 0 else (a, c, b))
        faces.append((n + a, n + c, n + b) if _signed(poly) > 0 else (n + a, n + b, n + c))
    parts = [Part(verts, faces, mat, False)]
    side = side_mat or mat
    sv, sf = [], []
    rings = [(face, -half), (poly, -half + bevel), (poly, half - bevel), (face, half)] if bevel > 0 \
        else [(poly, -half), (poly, half)]
    for outline, y in rings:
        for (x, z) in outline:
            sv.append((x, y, z))
    for r in range(len(rings) - 1):
        for i in range(n):
            a, b = r * n + i, r * n + (i + 1) % n
            c, d = a + n, b + n
            if _signed(poly) > 0:
                sf += [(a, c, b), (b, c, d)]
            else:
                sf += [(a, b, c), (b, d, c)]
    parts.append(Part(sv, sf, side, False))
    return parts


def _signed(poly):
    return sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
               for i in range(len(poly)))


def rounded_rect(w, h, r, steps=6):
    """A rounded rectangle centred on 0, as (x, z) points counter-clockwise."""
    pts = []
    for cx, cz, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90),
                       (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(steps + 1):
            a = math.radians(a0 + 90 * k / steps)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def arc(cx, cz, r, a0, a1, steps):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / steps)),
             cz + r * math.sin(math.radians(a0 + (a1 - a0) * k / steps))) for k in range(steps + 1)]


def star(points, r_out, r_in, cx=0.0, cz=0.0, turn=90.0):
    pts = []
    for k in range(points * 2):
        r = r_out if k % 2 == 0 else r_in
        a = math.radians(turn + 180.0 * k / points)
        pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


# ---------------------------------------------------------------- materials
def material(color, spec=0.4, shine=32.0, metal=False, rim=0.0, rim_color=(1, 1, 1), alpha=1.0,
             glow=0.0, rough=None, sheen=None):
    return {'color': np.array(color, dtype=float) / (255.0 if max(color) > 1 else 1.0), 'spec': spec,
            'shine': shine, 'metal': metal, 'rim': rim, 'rim_color': np.array(rim_color, dtype=float),
            'alpha': alpha, 'glow': glow, 'rough': rough, 'sheen': sheen}


# ---------------------------------------------------------------- camera
class Camera:
    def __init__(self, yaw=-30.0, pitch=20.0, dist=60.0, fov=30.0, target=(0, 0, 0), roll=0.0, ortho=None):
        self.target = np.asarray(target, dtype=float)
        y, p = math.radians(yaw), math.radians(pitch)
        self.eye = self.target + dist * np.array([math.cos(p) * math.sin(y), -math.cos(p) * math.cos(y),
                                                  math.sin(p)])
        fwd = self.target - self.eye
        self.fwd = fwd / np.linalg.norm(fwd)
        right = np.cross(self.fwd, [0, 0, 1.0])
        right /= np.linalg.norm(right)
        up = np.cross(right, self.fwd)
        rr = math.radians(roll)
        self.right = right * math.cos(rr) + up * math.sin(rr)
        self.up = up * math.cos(rr) - right * math.sin(rr)
        self.fov = fov
        self.ortho = ortho

    def project(self, pts, w, h, zoom=1.0):
        rel = pts - self.eye
        x, y, z = rel @ self.right, rel @ self.up, rel @ self.fwd
        if self.ortho:
            f = min(w, h) / self.ortho * zoom
            return w / 2 + f * x, h / 2 - f * y, z
        f = (min(w, h) / 2) / math.tan(math.radians(self.fov) / 2) * zoom
        return w / 2 + f * x / z, h / 2 - f * y / z, z


LIGHTS = [  # direction toward the light, colour, strength
    (np.array([-0.55, -0.55, 0.65]), np.array([1.0, 0.97, 0.92]), 1.0),  # key: top left, in front
    (np.array([0.75, -0.25, 0.15]), np.array([0.70, 0.78, 1.0]), 0.35),   # fill: right
    (np.array([0.2, 0.9, 0.4]), np.array([1.0, 1.0, 1.0]), 0.45),         # rim: behind
]
AMBIENT = 0.28


def _shade(mat, n, view):
    base = mat['color']
    out = base * AMBIENT
    for d, col, k in LIGHTS:
        d = d / np.linalg.norm(d)
        lam = np.clip(n @ d, 0, None)[:, None]
        diffuse = base * (0.6 if mat['metal'] else 1.0)
        out = out + diffuse * col * lam * k
        h = d + view
        h = h / np.linalg.norm(h, axis=1, keepdims=True)
        sp = np.clip(np.sum(n * h, axis=1), 0, None) ** mat['shine']
        tint = base if mat['metal'] else np.ones(3)
        out = out + (sp[:, None] * mat['spec'] * k) * tint * col
    if mat['metal']:  # a bright sky above and a dim floor below, reflected
        sky = np.clip(0.5 + 0.5 * n[:, 2], 0, 1)[:, None]
        out = out + base * (0.25 + 0.45 * sky)
    facing = np.clip(np.sum(n * view, axis=1), 0, 1)
    if mat['rim']:
        out = out + ((1 - facing) ** 2.5)[:, None] * mat['rim'] * mat['rim_color']
    if mat['sheen'] is not None:  # nacre: a soft colour shift with the angle
        a, b = mat['sheen']
        t = (n @ np.array([0.6, -0.3, 0.75]))[:, None]
        out = out + 0.10 * (np.array(a) * np.clip(t, 0, 1) + np.array(b) * np.clip(-t, 0, 1))
    if mat['glow']:
        out = out + base * mat['glow']
    return np.clip(out, 0, 1)


SMALL = 6        # triangles whose box fits in SMALL x SMALL pixels are drawn in batches
CHUNK = 40000    # ...this many at a time


def render(parts, mats, cam, size=256, zoom=1.0, ss=2, return_depth=False):
    """An RGBA image of the parts, supersampled `ss` times. Small opaque
    triangles (most of a fine mesh) are rasterized together with numpy; large
    and transparent ones one by one."""
    w = h = size * ss
    zbuf = np.full((h, w), np.inf)
    color = np.zeros((h, w, 3))
    alpha = np.zeros((h, w))
    later = []
    batch = []
    for part in parts:
        mat = mats[part.mat]
        vn = part.vertex_normals() if part.smooth else None
        sx, sy, sz = cam.project(part.v, w, h, zoom)
        if mat['alpha'] >= 1 and len(part.f):
            f = part.f
            bw = np.ceil(np.max(sx[f], axis=1)) - np.floor(np.min(sx[f], axis=1))
            bh = np.ceil(np.max(sy[f], axis=1)) - np.floor(np.min(sy[f], axis=1))
            small = (bw < SMALL) & (bh < SMALL)
            batch.append((part, mat, vn, sx, sy, sz, np.nonzero(small)[0]))
            loop = np.nonzero(~small)[0]
        else:
            loop = range(len(part.f))
        for fi in loop:
            i0, i1, i2 = part.f[fi]
            item = (part, mat, vn, fi, (i0, i1, i2), sx, sy, sz)
            if mat['alpha'] < 1:
                later.append((float(sz[[i0, i1, i2]].mean()), item))
            else:
                _raster(item, cam, zbuf, color, alpha, w, h, blend=False)
    for part, mat, vn, sx, sy, sz, idx in batch:
        for start in range(0, len(idx), CHUNK):
            _raster_batch(part, mat, vn, sx, sy, sz, idx[start:start + CHUNK], cam, zbuf, color, alpha, w, h)
    for _, item in sorted(later, key=lambda t: -t[0]):
        _raster(item, cam, zbuf, color, alpha, w, h, blend=True)
    rgba = np.dstack([color, alpha])
    if ss > 1:
        rgba = rgba.reshape(size, ss, size, ss, 4)
        premul = rgba[..., :3] * rgba[..., 3:4]
        a = rgba[..., 3].mean(axis=(1, 3))
        c = premul.mean(axis=(1, 3)) / np.maximum(a, 1e-6)[..., None]
        rgba = np.dstack([c, a])
    result=Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), 'RGBA')
    return (result,zbuf) if return_depth else result


def _raster_batch(part, mat, vn, sx, sy, sz, idx, cam, zbuf, color, alpha, w, h):
    """Many small triangles of one part at once: every candidate pixel of each
    triangle's box, the depth test through one scatter-min, then the winners
    shaded together."""
    if not len(idx):
        return
    f = part.f[idx]
    ax, bx, cx = sx[f[:, 0]], sx[f[:, 1]], sx[f[:, 2]]
    ay, by, cy = sy[f[:, 0]], sy[f[:, 1]], sy[f[:, 2]]
    az, bz, cz = sz[f[:, 0]], sz[f[:, 1]], sz[f[:, 2]]
    area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
    keep = (np.abs(area) > 1e-9) & (np.minimum(np.minimum(az, bz), cz) > 0.01)
    if not keep.any():
        return
    f, ax, bx, cx, ay, by, cy, az, bz, cz, area = (v[keep] for v in (f, ax, bx, cx, ay, by, cy, az, bz, cz, area))
    tri = np.arange(len(f))
    x0 = np.floor(np.minimum(np.minimum(ax, bx), cx)).astype(np.int64)
    y0 = np.floor(np.minimum(np.minimum(ay, by), cy)).astype(np.int64)
    ox, oy = np.meshgrid(np.arange(SMALL), np.arange(SMALL))
    ox, oy = ox.ravel(), oy.ravel()
    T = np.repeat(tri, len(ox))
    px = np.repeat(x0, len(ox)) + np.tile(ox, len(tri))
    py = np.repeat(y0, len(oy)) + np.tile(oy, len(tri))
    gx, gy = px + 0.5, py + 0.5
    A, B, C = ax[T], bx[T], cx[T]
    D, E, F = ay[T], by[T], cy[T]
    ar = area[T]
    w0 = ((B - gx) * (F - gy) - (C - gx) * (E - gy)) / ar
    w1 = ((C - gx) * (D - gy) - (A - gx) * (F - gy)) / ar
    w2 = 1 - w0 - w1
    inside = (w0 >= -1e-7) & (w1 >= -1e-7) & (w2 >= -1e-7) & (px >= 0) & (px < w) & (py >= 0) & (py < h)
    if not inside.any():
        return
    T, px, py, w0, w1, w2 = T[inside], px[inside], py[inside], w0[inside], w1[inside], w2[inside]
    zi = (w0*az[T]+w1*bz[T]+w2*cz[T]) if cam.ortho else 1.0 / (w0 / az[T] + w1 / bz[T] + w2 / cz[T])
    flat = py * w + px
    zf = zbuf.reshape(-1)
    before = zf[flat].copy()
    np.minimum.at(zf, flat, zi)
    win = (zi <= zf[flat]) & (zi < before)
    if not win.any():
        return
    T, flat, w0, w1, w2 = T[win], flat[win], w0[win], w1[win], w2[win]
    fv = f[T]
    v = part.v
    centre = (v[fv[:, 0]] + v[fv[:, 1]] + v[fv[:, 2]]) / 3
    view = cam.eye - centre
    view = view / np.linalg.norm(view, axis=1, keepdims=True)
    if vn is not None:
        n = w0[:, None] * vn[fv[:, 0]] + w1[:, None] * vn[fv[:, 1]] + w2[:, None] * vn[fv[:, 2]]
    else:
        n = np.cross(v[fv[:, 1]] - v[fv[:, 0]], v[fv[:, 2]] - v[fv[:, 0]])
    n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    flip = np.sum(n * view, axis=1) < 0
    n[flip] = -n[flip]
    color.reshape(-1, 3)[flat] = _shade(mat, n, view)
    alpha.reshape(-1)[flat] = 1.0


def _raster(item, cam, zbuf, color, alpha, w, h, blend):
    part, mat, vn, fi, idx, sx, sy, sz = item
    i0, i1, i2 = idx
    if min(sz[i0], sz[i1], sz[i2]) <= 0.01:
        return
    ax, bx, cx = sx[i0], sx[i1], sx[i2]
    ay, by, cy = sy[i0], sy[i1], sy[i2]
    area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
    if abs(area) < 1e-9:
        return
    x0, x1 = int(max(0, math.floor(min(ax, bx, cx)))), int(min(w - 1, math.ceil(max(ax, bx, cx))))
    y0, y1 = int(max(0, math.floor(min(ay, by, cy)))), int(min(h - 1, math.ceil(max(ay, by, cy))))
    if x0 > x1 or y0 > y1:
        return
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    w0 = ((bx - gx) * (cy - gy) - (cx - gx) * (by - gy)) / area
    w1 = ((cx - gx) * (ay - gy) - (ax - gx) * (cy - gy)) / area
    w2 = 1 - w0 - w1
    inside = (w0 >= -1e-7) & (w1 >= -1e-7) & (w2 >= -1e-7)
    if not inside.any():
        return
    zi = (w0*sz[i0]+w1*sz[i1]+w2*sz[i2]) if cam.ortho else 1.0 / (w0 / sz[i0] + w1 / sz[i1] + w2 / sz[i2])
    sub = zbuf[y0:y1 + 1, x0:x1 + 1]
    hit = inside & (zi < sub)
    if not hit.any():
        return
    tri = part.v[[i0, i1, i2]]
    fn = np.cross(tri[1] - tri[0], tri[2] - tri[0])
    fn = fn / (np.linalg.norm(fn) or 1)
    view = cam.eye - tri.mean(axis=0)
    view = view / np.linalg.norm(view)
    if vn is not None:
        n = (w0[hit][:, None] * vn[i0] + w1[hit][:, None] * vn[i1] + w2[hit][:, None] * vn[i2])
        n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    else:
        n = np.repeat(fn[None, :], int(hit.sum()), axis=0)
    flip = (n @ view) < 0  # seen from behind (an open tube end, a thin sheet)
    n[flip] = -n[flip]
    views = np.repeat(view[None, :], len(n), axis=0)
    shaded = _shade(mat, n, views)
    region = color[y0:y1 + 1, x0:x1 + 1]
    acover = alpha[y0:y1 + 1, x0:x1 + 1]
    if blend:
        a = mat['alpha']
        region[hit] = shaded * a + region[hit] * (1 - a)
        acover[hit] = a + acover[hit] * (1 - a)
    else:
        sub[hit] = zi[hit]
        region[hit] = shaded
        acover[hit] = 1.0


# ---------------------------------------------------------------- icons
OUTLINE = (25, 22, 26, 255)


def icon(img, outline=True, cutoff=0.5):
    """A rendered image brought down to the 32x32 item grid: averaged pixels,
    hard alpha, and Isaac's dark contour round the silhouette when asked."""
    small = img.resize((32, 32), Image.BOX)
    arr = np.array(small).astype(float)
    a = arr[..., 3] / 255.0
    rgb = arr[..., :3]
    solid = a >= cutoff
    out = np.zeros((32, 32, 4), dtype=np.uint8)
    out[solid, :3] = np.clip(rgb[solid], 0, 255)
    out[solid, 3] = 255
    if outline:
        edge = np.zeros_like(solid)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            edge |= np.roll(np.roll(solid, dy, 0), dx, 1)
        edge &= ~solid
        out[edge] = OUTLINE
    return Image.fromarray(out, 'RGBA')


def fit_zoom(parts, mats, cam, size=128, margin=0.10):
    """The zoom that makes the model fill the frame, `margin` left round it."""
    pts = np.vstack([p.v for p in parts])
    sx, sy, _ = cam.project(pts, size, size, 1.0)
    span = max(sx.max() - sx.min(), sy.max() - sy.min())
    zoom = size * (1 - 2 * margin) / span
    return zoom, ((sx.min() + sx.max()) / 2 - size / 2, (sy.min() + sy.max()) / 2 - size / 2)


def centred(parts, cam):
    """The parts moved so their middle sits on the camera's target."""
    pts = np.vstack([p.v for p in parts])
    mid = (pts.min(axis=0) + pts.max(axis=0)) / 2
    return move(parts, T(*(cam.target - mid)))


# ---------------------------------------------------------------- glTF
def export_glb(parts, mats, path):
    groups = {}
    for part in parts:
        groups.setdefault(part.mat, []).append(part)
    blob = bytearray()
    views, accessors, meshes_prims, materials = [], [], [], []
    names = sorted(groups)
    for mi, name in enumerate(names):
        m = mats[name]
        pos, nor, idx = [], [], []
        base = 0
        for part in groups[name]:
            if part.smooth:
                v, n, f = part.v, part.vertex_normals(), part.f
            else:
                tri = part.v[part.f]
                fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
                fn = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
                v = tri.reshape(-1, 3)
                n = np.repeat(fn, 3, axis=0)
                f = np.arange(len(v)).reshape(-1, 3)
            pos.append(v)
            nor.append(n)
            idx.append(f + base)
            base += len(v)
        pos = np.vstack(pos)
        nor = np.vstack(nor)
        idx = np.vstack(idx)
        # Weld identical position/normal pairs, especially subdivided hard
        # faces. Four decimal places are far below one native pixel; float
        # noise otherwise bloats the embedded review without visible detail.
        packed,inverse=np.unique(np.round(np.column_stack([pos,nor]),4),axis=0,return_inverse=True)
        pos,nor=packed[:,:3],packed[:,3:]
        idx=inverse[idx]
        pos = np.stack([pos[:, 0], pos[:, 2], -pos[:, 1]], axis=1).astype(np.float32)
        nor = np.stack([nor[:, 0], nor[:, 2], -nor[:, 1]], axis=1).astype(np.float32)
        idx = idx.astype(np.uint32).reshape(-1)
        acc = {}
        for key, data, target, kind in (('POSITION', pos, 34962, 'VEC3'), ('NORMAL', nor, 34962, 'VEC3'),
                                        ('indices', idx, 34963, 'SCALAR')):
            while len(blob) % 4:
                blob.append(0)
            raw = data.tobytes()
            views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(raw), 'target': target})
            blob += raw
            a = {'bufferView': len(views) - 1, 'componentType': 5125 if key == 'indices' else 5126,
                 'count': len(data) if key == 'indices' else len(data), 'type': kind}
            if key == 'POSITION':
                a['min'] = pos.min(axis=0).tolist()
                a['max'] = pos.max(axis=0).tolist()
            accessors.append(a)
            acc[key] = len(accessors) - 1
        meshes_prims.append({'attributes': {'POSITION': acc['POSITION'], 'NORMAL': acc['NORMAL']},
                             'indices': acc['indices'], 'material': mi})
        mat = {'name': name, 'doubleSided': True,
               'pbrMetallicRoughness': {'baseColorFactor': [*map(float, m['color']), float(m['alpha'])],
                                        'metallicFactor': 1.0 if m['metal'] else 0.0,
                                        'roughnessFactor': float(m['rough'] if m['rough'] is not None
                                                                 else max(0.08, 1.0 - m['spec']))}}
        if m['alpha'] < 1:
            mat['alphaMode'] = 'BLEND'
        if m['glow']:
            mat['emissiveFactor'] = [float(c * min(1.0, m['glow'])) for c in m['color']]
        materials.append(mat)
    doc = {'asset': {'version': '2.0', 'generator': "Conch's Blessing mesh3d.py"},
           'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'mesh': 0}],
           'meshes': [{'primitives': meshes_prims}], 'materials': materials,
           'buffers': [{'byteLength': len(blob)}], 'bufferViews': views, 'accessors': accessors}
    js = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    js += b' ' * (-len(js) % 4)
    while len(blob) % 4:
        blob.append(0)
    total = 12 + 8 + len(js) + 8 + len(blob)
    with open(path, 'wb') as fh:
        fh.write(struct.pack('<III', 0x46546C67, 2, total))
        fh.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        fh.write(struct.pack('<II', len(blob), 0x004E4942) + bytes(blob))
    return sum(len(p.f) for p in parts)
