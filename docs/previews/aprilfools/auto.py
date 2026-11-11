"""Reads an item icon into solids for its 1:1 April Fools model (2026-11-11).

What an icon draws is split three ways:
- ink: the near-black outline and inner lines, and the soft glow pixels
  (alpha under 128). They are line art around the object, so the April Fools
  icon keeps them exactly as shipped.
- bodies: every separate patch of the remaining pixels is one solid.
- materials: inside a body, colours that differ only in lightness or
  saturation are one material's light and shadow (the user, 2026-11-11: the
  sickle's dark gold, gold and cream are its shading), so they are one
  material, and the 3D lighting makes the shading. Only a clearly different
  colour family (a red gem on a gold crown, white eyes in a brown face) is a
  material of its own.
Each material's colour is the middle tone of its pixels, so the lighting's
lit and shaded sides bracket it the way the icon's shading did.
"""
import colorsys

import numpy as np
from PIL import Image
from scipy import ndimage

from mesh3d import material

INK_LUM = 27      # darker than this is ink wherever it is
EDGE_INK_LUM = 50  # darker than this is ink when it mostly rims the drawing
SOLID_ALPHA = 128  # softer pixels are glow
HUE_GAP = 28.0     # degrees: hues closer than this are one colour family
GREY_SAT = 0.22    # less saturated than this has no hue of its own


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def analyse(path):
    a = path if isinstance(path, np.ndarray) else np.array(Image.open(path).convert('RGBA'))
    rgb, alpha = a[..., :3].astype(int), a[..., 3]
    solid = alpha >= SOLID_ALPHA
    outside = ~solid
    near_outside = ndimage.binary_dilation(outside) & solid
    colours = {}
    for y, x in zip(*np.nonzero(solid)):
        colours.setdefault(tuple(rgb[y, x]), []).append((y, x))
    ink = np.zeros(solid.shape, dtype=bool)
    for c, pix in colours.items():
        l = lum(c)
        rim = sum(near_outside[y, x] for y, x in pix) / len(pix)
        if l < INK_LUM or (l < EDGE_INK_LUM and rim > 0.6 and len(pix) > 12):
            for y, x in pix:
                ink[y, x] = True
    # Only the outline round the drawing (ink touching the empty background,
    # diagonals too) is line art. Dark pixels inside it are real features:
    # pupils, nostrils, a dark face, a black frame. They stay in the model as
    # a near-black material (found 2026-11-11, when the full 3D renders lost
    # every eye).
    touching = ndimage.binary_dilation(outside, structure=np.ones((3, 3)))
    outline = ink & touching
    obj = solid & ~outline
    bodies, nbodies = ndimage.label(obj, structure=np.ones((3, 3)))
    return a, obj, ink & obj, bodies, nbodies


def _median(items):
    items = sorted(items, key=lambda t: lum(t[0]))
    half, run = sum(n for _, n in items) / 2, 0
    for c, n in items:
        run += n
        if run >= half:
            return c
    return items[-1][0]


def families(pixels, rgb):
    """Groups a body's colours into materials; returns [(colours, middle tone)].

    Colours of one hue family and similar saturation are one material in
    light and shadow. Kept apart: a hue family that splits into clearly
    different saturations (a pale muzzle on an ochre hide), white patches of
    three or more pixels (eyes, teeth, paper), large greys (a metal frame) and
    near-black areas that are not ink. Smaller whites, greys and darks are the
    main material's highlights and shadows."""
    counts = {}
    for y, x in pixels:
        c = tuple(int(v) for v in rgb[y, x])
        counts[c] = counts.get(c, 0) + 1
    total = sum(counts.values())
    hued, white, grey, dark = [], [], [], []
    for c, n in counts.items():
        h, s, v = colorsys.rgb_to_hsv(*(np.array(c) / 255.0))
        if v < 0.22:
            dark.append((c, n))
        elif s < 0.18 and v > 0.84:
            white.append((c, n))
        elif s < GREY_SAT:
            grey.append((c, n))
        else:
            hued.append((c, n, h * 360.0, s))
    groups = []
    for c, n, h, s in sorted(hued, key=lambda t: t[2]):
        for g in groups:
            if min(abs(h - g['hue']), 360 - abs(h - g['hue'])) < HUE_GAP:
                g['items'].append((c, n, s))
                g['hue'] = (g['hue'] * g['n'] + h * n) / (g['n'] + n)
                g['n'] += n
                break
        else:
            groups.append({'hue': h, 'n': n, 'items': [(c, n, s)]})
    if len(groups) > 1:
        a, b = groups[0], groups[-1]
        if min(abs(a['hue'] - b['hue']), 360 - abs(a['hue'] - b['hue'])) < HUE_GAP:
            a['items'] += b['items']
            a['n'] += b['n']
            groups.pop()
    materials = []
    for g in groups:
        items = sorted(g['items'], key=lambda t: t[2])
        sats = [s for _, _, s in items]
        cut = None
        for k in range(1, len(items)):
            if sats[k] - sats[k - 1] > 0.22 and sats[-1] - sats[0] > 0.35:
                cut = k
        parts = [items[:cut], items[cut:]] if cut else [items]
        for part in parts:
            if sum(n for _, n, _ in part) >= 3 or not materials:
                materials.append({'core': [(c, n) for c, n, _ in part], 'all': [(c, n) for c, n, _ in part]})
            else:
                materials[-1]['all'] += [(c, n) for c, n, _ in part]
    main = max(range(len(materials)), key=lambda i: sum(n for _, n in materials[i]['core'])) if materials else None
    for kind, items, keep in (('white', white, 3), ('grey', grey, max(4, int(0.15 * total))), ('dark', dark, 3)):
        n = sum(k for _, k in items)
        if not items:
            continue
        if n >= keep or main is None:
            materials.append({'core': items, 'all': list(items)})
        else:
            materials[main]['all'] += items
    # a material's colour is the middle tone of its own colours; the specks,
    # highlights and shadows merged into it shade it but never choose it
    return [([c for c, _ in m['all']], _median(m['core'])) for m in materials]


def material_for(c):
    h, s, v = colorsys.rgb_to_hsv(*(np.array(c) / 255.0))
    h *= 360
    if 30 <= h <= 62 and s > 0.55 and v > 0.45:  # gold
        return material(c, spec=0.9, shine=45, metal=True)
    if 160 <= h <= 210 and v > 0.55:  # glass and lenses
        return material(c, spec=0.95, shine=80, glow=0.15)
    if s < GREY_SAT and v > 0.7:  # pale: porcelain, pearl, paper
        return material(c, spec=0.6, shine=40)
    return material(c, spec=0.35, shine=24)


def auto_spec(path, profile='round', thickness=3.0, overrides=None):
    """(labels, info, mats, object mask) for relief_from_labels."""
    overrides = dict(overrides or {})
    # hand groupings: each listed set of colours (hex) is one material, its
    # colour the set's middle tone; the rest is grouped automatically
    groups = [{tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in g} for g in overrides.pop('groups', [])]
    a, obj, inner_ink, bodies, nbodies = analyse(path)
    rgb = a[..., :3].astype(int)
    labels = np.zeros(a.shape[:2], dtype=np.int64)
    info, mats = [], {}
    for b in range(1, nbodies + 1):
        pixels = list(zip(*np.nonzero(bodies == b)))
        found = []
        rest = []
        for g in groups:
            counts = {}
            for y, x in pixels:
                c = tuple(int(v) for v in rgb[y, x])
                if c in g:
                    counts[c] = counts.get(c, 0) + 1
            if counts:
                found.append((list(counts), _median(list(counts.items()))))
        taken = {c for cs, _ in found for c in cs}
        rest = [(y, x) for y, x in pixels if tuple(int(v) for v in rgb[y, x]) not in taken]
        for colours, mid in found + (families(rest, rgb) if rest else []):
            name = 'm%02x%02x%02x' % mid
            mats.setdefault(name, material_for(mid))
            info.append({'mat': name, 'body': b, 'profile': profile, 'thickness': thickness, 'lum': lum(mid),
                         **overrides})
            idx = len(info)
            cs = set(colours)
            for y, x in pixels:
                if tuple(int(v) for v in rgb[y, x]) in cs:
                    labels[y, x] = idx
    return labels, info, mats, obj, carving(rgb, labels, info, inner_ink, bodies)


SHADE_DEPTH = 0.6   # px a part's darkest tone sinks
GROOVE_DEPTH = 0.9  # px an inner line is cut in; a wider dark area sinks up to 1.6
INLAY = 0.45        # px a small part (eyes, a muzzle, horns) stands proud of its body


def carving(rgb, labels, info, inner_ink, bodies):
    """The carved detail, in icon pixels toward the viewer, read from the
    icon itself: inside one material its lighter tones are surfaces turned to
    the light and its darker ones turned away, so they stand out and sink in;
    a dark line inside the drawing is a cut groove (a wider dark area a hollow);
    a part much smaller than its body stands proud of it like an inlay."""
    lumi = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    detail = np.zeros(labels.shape)
    for i in range(1, labels.max() + 1):
        region = labels == i
        if not region.any():
            continue
        values = lumi[region]
        mid = np.median(values)
        spread = max(values.max() - values.min(), 40.0)
        # only the darker tones sink: a highlight is a reflection, not a shape
        # (carving highlights raised a cross on the pearl, 2026-11-11)
        detail[region] -= SHADE_DEPTH * np.clip((mid - lumi[region]) / (spread / 2), 0, 1)
        body = bodies == bodies[region][0]
        if region.sum() < 0.25 * body.sum() and not inner_ink[region].all():
            detail[region] += INLAY
    if inner_ink.any():
        width = ndimage.distance_transform_edt(inner_ink)
        detail[inner_ink] -= GROOVE_DEPTH + np.clip(width[inner_ink] - 1.0, 0, 1.0) * 0.7
    return detail
