"""Parts built to the shipped icon's exact outlines (user request 2026-11-11:
"완전 1:1 매칭").

An item's icon is split into its physical parts by colour (a blade, its
ground edge, a cross...). Each part's outline is taken from those pixels and
smoothed, then given its own solid profile: a thin plate with chamfered rims,
a sharpened edge, or a round bar that swells to its own half-width. The
result is a closed mesh per part with its own material; no picture is painted
on it. Seen straight from the front through an orthographic camera the parts
cover exactly the icon's pixels, so the April Fools icon keeps the shipped
composition 1:1, while every other angle shows the solids.

Icon pixels map to the world as x = column, z = -row, so the icon's 32x32
grid is a 32-unit square in the x-z plane with y as depth.
"""
import numpy as np
from PIL import Image
from scipy import ndimage
from skimage.morphology import medial_axis

from mesh3d import Camera, Part, render

UP = 4  # sub-steps per icon pixel


def classes(path, groups):
    """{part name: 32x32 mask} from the icon: `groups` maps a part to the
    colours (RGB) its pixels have."""
    arr = np.array(Image.open(path).convert('RGBA'))
    rgb = arr[..., :3]
    out = {}
    for name, colours in groups.items():
        mask = np.zeros(arr.shape[:2], dtype=bool)
        for c in colours:
            mask |= np.all(rgb == np.array(c), axis=2) & (arr[..., 3] == 255)
        out[name] = mask
    return out


GROW = 3     # sub-steps the outline is pushed out before smoothing (0.75 px)...
SMOOTH = 1.2  # ...and how wide (px) the smoothing is: thin parts keep covering every pixel


def smooth_mask(mask, up=UP, grow=GROW, smooth=SMOOTH):
    big = np.kron(mask, np.ones((up, up), dtype=bool))
    if grow:
        big = ndimage.binary_dilation(big, iterations=grow)
    return ndimage.gaussian_filter(big.astype(float), sigma=up * smooth) >= 0.5


def height(mask, profile, thickness=1.0, slope=1.0, up=UP):
    """Half-thickness at every sub-step inside `mask`, smoothed inside the
    outline so the surface follows the part rather than the pixel steps."""
    h = _height(mask, profile, thickness, slope, up)
    soft = ndimage.gaussian_filter(h, sigma=up * 0.6)
    weight = ndimage.gaussian_filter(mask.astype(float), sigma=up * 0.6)
    return np.where(mask, np.minimum(h, soft / np.maximum(weight, 1e-3)), 0.0)


def _height(mask, profile, thickness=1.0, slope=1.0, up=UP):
    """Half-thickness at every sub-step inside `mask`, in icon pixels.
    round: a circle across the part's own local width (bars and balls);
    plate: flat at `thickness`/2 with chamfered rims `slope` steep;
    edge:  a sharpened rim, thinnest at the outside."""
    d = ndimage.distance_transform_edt(mask) / up
    if profile == 'round':
        # the local half-width: the distance kept on the shape's medial axis,
        # read at the nearest axis point, so a bar is a tube and a disc a ball
        if not mask.any():
            return np.zeros(mask.shape)
        skel, axis = medial_axis(mask, return_distance=True)
        near = ndimage.distance_transform_edt(~skel, return_distances=False, return_indices=True)
        r = np.maximum(axis[near[0], near[1]] / up, 1e-3)
        d = np.minimum(d, r)
        h = np.sqrt(np.clip(2 * r * d - d * d, 0, None))
        return np.where(mask, np.minimum(h, thickness), 0.0)
    if profile == 'plate':
        return np.where(mask, np.minimum(thickness / 2, d * slope), 0.0)
    if profile == 'edge':
        return np.where(mask, np.minimum(thickness / 2, d * slope * 0.5), 0.0)
    raise ValueError(profile)


def solid(mask, h, mat, depth=0.0, up=UP, relief=None):
    """A closed mesh over `mask`: the front surface at y = depth - h (pushed
    further out by `relief`, the carved detail), the back at y = depth + h,
    joined round the rim."""
    rows, cols = np.nonzero(mask)
    index = -np.ones(mask.shape, dtype=np.int64)
    index[rows, cols] = np.arange(len(rows))
    x = (cols + 0.5) / up
    z = -(rows + 0.5) / up
    hv = np.maximum(h[rows, cols], 0.02)
    hf = hv if relief is None else np.maximum(hv + relief[rows, cols], 0.03)
    front = np.stack([x, depth - hf, z], axis=1)
    back = np.stack([x, depth + hv, z], axis=1)
    n = len(rows)
    verts = np.vstack([front, back])
    faces = []
    a = index[:-1, :-1]
    b = index[:-1, 1:]
    c = index[1:, :-1]
    d = index[1:, 1:]
    ok1 = (a >= 0) & (b >= 0) & (c >= 0)
    ok2 = (b >= 0) & (d >= 0) & (c >= 0)
    t1 = np.stack([a[ok1], c[ok1], b[ok1]], axis=1)
    t2 = np.stack([b[ok2], c[ok2], d[ok2]], axis=1)
    tris = np.vstack([t1, t2])
    faces = np.vstack([tris, tris[:, ::-1] + n])
    # the rim: edges used by one triangle only, joined front to back
    directed = np.vstack([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
    keys = np.sort(directed, axis=1)
    code = keys[:, 0] * (2 * n + 1) + keys[:, 1]
    _, inverse, counts = np.unique(code, return_inverse=True, return_counts=True)
    edge = directed[counts[inverse] == 1]
    if len(edge):
        e0, e1 = edge[:, 0], edge[:, 1]
        rim = np.vstack([np.stack([e1, e0, e0 + n], axis=1), np.stack([e1, e0 + n, e1 + n], axis=1)])
        faces = np.vstack([faces, rim])
    return Part(verts, faces, mat, True)


def relief_parts(path, spec):
    """The parts of an icon as solids, chosen by colour. `spec` maps a part
    name to its colours (or a 32x32 `mask`), material, `body` (parts of one
    body share one height field, so they meet without a seam), and that
    body's profile (`profile`, `thickness`, `slope`, `grow`, `smooth`), the
    part's `scale` of the body's thickness and its `depth`."""
    order = list(spec)
    masks = classes(path, {k: spec[k].get('colors', []) for k in order})
    labels = np.zeros((32, 32), dtype=np.int64)
    for i, k in enumerate(order, 1):
        labels[spec[k]['mask'] if 'mask' in spec[k] else masks[k]] = i
    return relief_from_labels(labels, [spec[k] for k in order])


def fine_labels(labels, info):
    """The label map on the sub-step grid, smoothed: each body on its own, so
    a narrow gap between two bodies stays open; where two bodies' smoothed
    outlines meet, the nearer body's own pixels win, and inside one body the
    parts' borders are smoothed too. Returns (labels, {body: [label ids]})."""
    fine = np.kron(labels, np.ones((UP, UP), dtype=np.int64))
    bodies = {}
    for i, s in enumerate(info, 1):
        if (labels == i).any():
            bodies.setdefault(s.get('body', i), []).append(i)
    lab = np.zeros_like(fine)
    best = np.full(fine.shape, np.inf)
    for body, ids in bodies.items():
        first = info[ids[0] - 1]
        own = np.isin(fine, ids)
        region = smooth_mask(np.isin(labels, ids), grow=first.get('grow', GROW),
                             smooth=first.get('smooth', SMOOTH))
        dist = ndimage.distance_transform_edt(~own)
        take = region & (dist < best)
        best[take] = dist[take]
        if len(ids) == 1:
            lab[take] = ids[0]
        else:
            weights = [ndimage.gaussian_filter((fine == i).astype(float), sigma=UP * 0.8) for i in ids]
            pick = np.array(ids)[np.argmax(np.stack(weights), axis=0)]
            lab[take] = pick[take]
    return lab, bodies


def relief_from_labels(labels, info, detail=None):
    """Solids from a 32x32 label map (0 = not part of the object; label i is
    described by info[i - 1]). Each body is smoothed on its own, so a narrow
    gap between two bodies stays open; where two bodies' smoothed outlines
    meet, the nearer body's own pixels win, and inside one body the parts'
    borders are smoothed too."""
    lab, bodies = fine_labels(labels, info)
    heights = {}
    for body, ids in bodies.items():
        first = info[ids[0] - 1]
        heights[body] = height(np.isin(lab, ids), first.get('profile', 'plate'), first.get('thickness', 1.0),
                               first.get('slope', 1.0))
    carve = None
    if detail is not None:
        # the carved detail (icon pixels) brought to the sub-steps and softened,
        # so it reads as modelled form rather than square pixels, and faded to
        # nothing at the rim, where the solid is thin
        carve = ndimage.gaussian_filter(np.kron(detail, np.ones((UP, UP))), sigma=UP * 0.45)
    parts = []
    for body, ids in bodies.items():
        region_b = np.isin(lab, ids)
        fade = np.clip(ndimage.distance_transform_edt(region_b) / (UP * 1.2), 0, 1) if carve is not None else None
        for i in ids:
            s = info[i - 1]
            region = lab == i
            if region.any():
                parts.append(solid(region, heights[body] * s.get('scale', 1.0), s['mat'],
                                   depth=s.get('depth', 0.0),
                                   relief=None if carve is None else carve * fade))
    return parts


def front_view(parts, mats, size=256, ss=2, w=32, h=32):
    """The parts straight from the front, framed exactly on a w x h grid of
    icon pixels (`size` image pixels across the longer side)."""
    side = max(w, h)
    cam = Camera(yaw=0.0, pitch=0.0, dist=400.0, target=(w / 2, 0.0, -h / 2), ortho=float(side))
    img = render(parts, mats, cam, size=size, zoom=1.0, ss=ss)
    k = size / side
    left, top = round((side - w) / 2 * k), round((side - h) / 2 * k)
    return img.crop((left, top, left + round(w * k), top + round(h * k)))


def spin_view(parts, mats, yaw, size=256, ss=2, w=32, h=32, centre=None):
    """The parts turned `yaw` degrees about the upright axis through their
    middle, from the front, on the same w x h framing as front_view."""
    side = max(w, h)
    cx, cy = centre if centre is not None else (w / 2, 0.0)
    cam = Camera(yaw=yaw, pitch=0.0, dist=400.0, target=(cx, cy, -h / 2), ortho=float(side))
    img = render(parts, mats, cam, size=size, zoom=1.0, ss=ss)
    k = size / side
    shift = round((cx - w / 2) * k)  # keep the turning axis where the item stands
    left, top = round((side - w) / 2 * k) - shift, round((side - h) / 2 * k)
    return img.crop((left, top, left + round(w * k), top + round(h * k)))


def _image(src):
    if isinstance(src, np.ndarray):
        return src
    if isinstance(src, Image.Image):
        return np.array(src.convert('RGBA'))
    return np.array(Image.open(src).convert('RGBA'))


def one_to_one(shipped, hero, part_colors=(), coloured=None):
    """The April Fools picture, 1:1 with the shipped one: the shipped
    picture's own outline and glow stay where they are, and each pixel of the
    object takes the colour the 3D render has there (averaged over the pixel).
    A pixel the render does not cover takes its nearest covered neighbour's
    colour."""
    ship = _image(shipped)
    hh, ww = ship.shape[:2]
    if coloured is None:
        coloured = np.zeros(ship.shape[:2], dtype=bool)
        for c in part_colors:
            coloured |= np.all(ship[..., :3] == np.array(c), axis=2) & (ship[..., 3] == 255)
    big = np.array(hero).astype(float) / 255.0
    k = big.shape[1] // ww
    big = big[:hh * k, :ww * k]
    a = big[..., 3]
    pre = big[..., :3] * a[..., None]
    a_s = a.reshape(hh, k, ww, k).mean(axis=(1, 3))
    rgb_s = pre.reshape(hh, k, ww, k, 3).mean(axis=(1, 3)) / np.maximum(a_s, 1e-6)[..., None]
    covered = a_s >= 0.5
    if not covered.any():
        return Image.fromarray(ship, 'RGBA'), int(coloured.sum())
    near = ndimage.distance_transform_edt(~covered, return_distances=False, return_indices=True)
    fill = rgb_s[near[0], near[1]]
    out = ship.copy()
    out[coloured, :3] = np.clip(fill[coloured] * 255, 0, 255).astype(np.uint8)  # its own alpha stays
    return Image.fromarray(out, 'RGBA'), int((coloured & ~covered).sum())


def compare(shipped_path, april, ignore_alpha_below=255):
    """How closely the rendered icon covers the shipped one: the share of the
    shipped icon's solid pixels (outline included) that are solid in both,
    and of all pixels whose solidity agrees."""
    a = _image(shipped_path)[..., 3] >= ignore_alpha_below
    b = np.array(april)[..., 3] >= ignore_alpha_below
    both = (a & b).sum()
    return {'iou': both / max(1, (a | b).sum()), 'agree': (a == b).mean(), 'missing': int((a & ~b).sum()),
            'extra': int((b & ~a).sum())}
