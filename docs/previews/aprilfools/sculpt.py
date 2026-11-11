"""The v2 modeller: the item modelled the way a production artist would block
and sculpt it from a 2D concept, kept 1:1 with the icon from the front
(user request 2026-11-11: learn the techniques used in real 3D work, match
1:1, then make it look right from every side).

What it takes from production practice:
- Orthographic blocking: the front view is the reference (the icon itself);
  the side view, which the icon does not show, is designed per part. A part
  is inflated round its own centre line, the way sketch-based modellers
  (Teddy, Monster Mash) turn a drawn outline into a volume, so its
  cross-sections are round: a head reads as a head from the side and a horn as
  a horn, not as a flat cookie. Flat things (paper, cards, coins, blades) keep
  a thin profile instead.
- SDF sculpting and voxel remeshing (ZBrush DynaMesh, Dreams, Womp): every
  body is a signed distance field; bodies are joined with a smooth union, so
  where two parts meet they melt into one surface instead of a seam, and the
  whole field is meshed once by marching cubes into a clean closed mesh.
- Primary, secondary and tertiary forms: the bodies are the primary forms,
  their parts (a muzzle, eyes, horns) the secondary forms raised on them, and
  the icon's own shading and lines are carved in last as surface detail.
- Materials stay by part: the colour of the part the icon gives at that spot.
"""
import numpy as np
from scipy import ndimage
from skimage import measure
from skimage.morphology import medial_axis

from mesh3d import Part
from relief import UP, fine_labels

BLEND = 0.7       # px: how far two bodies melt into each other
RIM = 0.35        # px: how round a part's rim is where front meets back
DEPTH = 0.85      # a round part is this deep for its width (1 = circular)
BACK = 0.9        # the back is a little flatter than the front


def smin(a, b, k):
    """Polynomial smooth minimum (a smooth union of two distance fields)."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def _profile(region, profile, thickness, up=UP):
    """Half-depth (px) over a body's region on the sub-step grid."""
    d = ndimage.distance_transform_edt(region) / up
    if profile == 'plate':
        return np.where(region, np.minimum(thickness / 2, d * 1.2), 0.0)
    skel, axis = medial_axis(region, return_distance=True)
    if not skel.any():
        return np.where(region, d, 0.0)
    near = ndimage.distance_transform_edt(~skel, return_distances=False, return_indices=True)
    r = np.maximum(axis[near[0], near[1]] / up, 1e-3)
    # the radius jumps where the centre line branches, which left creases
    # across the surface; spread it smoothly over the part
    weight = ndimage.gaussian_filter(region.astype(float), sigma=up * 1.0)
    r = np.where(region, ndimage.gaussian_filter(np.where(region, r, 0.0), sigma=up * 1.0)
                 / np.maximum(weight, 1e-3), r)
    dd = np.minimum(d, r)
    h = DEPTH * np.sqrt(np.clip(2 * r * dd - dd * dd, 0, None))
    if thickness is not None:
        h = np.minimum(h, thickness)
    soft = ndimage.gaussian_filter(h, sigma=up * 0.6)
    weight = ndimage.gaussian_filter(region.astype(float), sigma=up * 0.6)
    return np.where(region, np.minimum(h, soft / np.maximum(weight, 1e-3)), 0.0)


def sculpt(labels, info, mats, detail=None):
    """Closed meshes, one Part per material, for the label map `labels` (see
    relief.relief_from_labels for `info`)."""
    lab, bodies = fine_labels(labels, info)
    H, W = lab.shape
    carve = None
    if detail is not None:
        carve = ndimage.gaussian_filter(np.kron(detail, np.ones((UP, UP))), sigma=UP * 0.45)
    fields = []
    reach = 1.0
    for body, ids in bodies.items():
        region = np.isin(lab, ids)
        first = info[ids[0] - 1]
        thick = first.get('thickness')
        profile = 'plate' if first.get('profile') == 'plate' else 'round'
        if profile == 'round' and first.get('flat'):
            profile = 'plate'
            thick = first.get('flat')
        half = _profile(region, profile, thick if profile == 'plate' else first.get('cap'))
        front = half.copy()
        if carve is not None:
            fade = np.clip(ndimage.distance_transform_edt(region) / (UP * 1.2), 0, 1)
            front = np.maximum(front + carve * fade, 0.03)
        back = half * BACK
        depth = first.get('depth', 0.0)
        d_in = ndimage.distance_transform_edt(region) / UP
        d_out = ndimage.distance_transform_edt(~region) / UP
        sd2 = d_out - d_in
        fields.append((sd2, front, back, depth))
        reach = max(reach, float(front.max()) + abs(depth) + 1.0, float(back.max()) + abs(depth) + 1.0)
    # the depth axis on the same sub-steps
    ys = np.arange(-reach, reach + 1e-9, 1.0 / UP)
    total = None
    for sd2, front, back, depth in fields:
        Y = ys[None, None, :]
        slab = np.maximum((depth - Y) - front[..., None], (Y - depth) - back[..., None])
        f = smax(sd2[..., None] + np.zeros_like(Y), slab, RIM)
        total = f if total is None else smin(total, f, BLEND)
    pad = np.full((H + 2, W + 2, len(ys) + 2), 10.0)
    pad[1:-1, 1:-1, 1:-1] = total
    verts, faces, normals, _ = measure.marching_cubes(pad, level=0.0)
    # grid (row, col, depth step) -> world (x = column, y = depth, z = -row), in icon pixels
    row = (verts[:, 0] - 1 + 0.5) / UP
    col = (verts[:, 1] - 1 + 0.5) / UP
    dep = ys[0] + (verts[:, 2] - 1) / UP
    v = np.stack([col, dep, -row], axis=1)
    # each face takes the material of the part the icon has there
    r_i = np.clip(np.round(verts[:, 0] - 1).astype(int), 0, H - 1)
    c_i = np.clip(np.round(verts[:, 1] - 1).astype(int), 0, W - 1)
    near = ndimage.distance_transform_edt(lab == 0, return_distances=False, return_indices=True)
    vlab = lab[near[0][r_i, c_i], near[1][r_i, c_i]]
    # the back is the body's own skin: features drawn on the icon's front
    # (eyes, a muzzle, stripes' dark lines) stay on the front half
    base = {}
    for body, ids in bodies.items():
        # the skin is the colour filling the body's middle (a face, not the
        # antlers round it), leaving out dark features
        region = np.isin(lab, ids)
        d = ndimage.distance_transform_edt(region)
        core = region & (d >= 0.5 * d.max())
        light = [i for i in ids if info[i - 1].get('lum', 255) >= 40] or ids
        counts = {i: int(((lab == i) & core).sum()) for i in light}
        if not any(counts.values()):
            counts = {i: int((lab == i).sum()) for i in light}
        base[body] = max(counts, key=counts.get)
    body_of = {i: body for body, ids in bodies.items() for i in ids}
    depth_of = {body: info[ids[0] - 1].get('depth', 0.0) for body, ids in bodies.items()}
    area = {i: int((lab == i).sum()) for i in body_of}
    body_area = {body: int(np.isin(lab, ids).sum()) for body, ids in bodies.items()}
    for i in np.unique(vlab):
        if i == 0:
            continue
        b = body_of[i]
        feature = info[i - 1].get('lum', 255) < 40 or area[i] < 0.12 * body_area[b]
        if feature:  # eyes, dark lines, small inlays: only on the front
            behind = (vlab == i) & (dep > depth_of[b])
            vlab[behind] = base[b]
    flab = vlab[faces[:, 0]]
    parts = []
    for i in np.unique(flab):
        if i == 0:
            continue
        sel = faces[flab == i]
        used = np.unique(sel)
        remap = -np.ones(len(v), dtype=np.int64)
        remap[used] = np.arange(len(used))
        parts.append(Part(v[used], remap[sel], info[i - 1]['mat'], True))
    # every face outward, so other viewers light the .glb from the right side
    allv = np.vstack([p.v for p in parts]) if parts else np.zeros((1, 3))
    centre = allv.mean(axis=0)
    for p in parts:
        n = p.vertex_normals()
        if np.mean(np.sum(n * (p.v - centre), axis=1)) < 0:
            p.f = p.f[:, ::-1]
    return parts
