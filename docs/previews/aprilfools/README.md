# April Fools 3D

The current revision builds objects from physical components: skull and muzzle,
articulated limbs, a hollow spiral shell, diamond-section cutting blades,
wrapped cylindrical grips, a zipped transparent pouch with individual pills,
complete belt/crown bands, objective barrels and a shallow ceramic plate.
Side and rear surfaces are constructed interpretations of those objects.
Whole-sprite inflation is no longer part of the production pipeline.

Front silhouettes, proportions and markings are compared with the shipped
sprites. Original interior ink conforms to the first visible model surface;
it is not wrapped around hidden sides or stamped onto the back. Painted
highlights never drive geometry. Thin paper and architectural panels are
legitimate thin solids, with edges, reverse faces and preserved openings.
The pearl is a true sphere. Source registration and mesh density do not
by themselves establish exact 1:1 fidelity or a finished aesthetic result.

## Build and review

From the repository root (Python with Pillow, NumPy, SciPy and scikit-image):

```text
python docs/previews/aprilfools/build.py
python docs/previews/aprilfools/actors.py
python docs/previews/aprilfools/extras.py
python docs/previews/aprilfools/catalogue.py
python docs/previews/aprilfools/review.py
python docs/previews/aprilfools/inspection.py
python -m unittest discover -s tests -p test_april_fools.py -v
```

`objects.py` owns component construction and geometry-conforming source ink.
`recipes.py` supplies mesh helpers and the smaller all-around object recipes.
`build.py` exports GLB sources and 32-frame item turntables. `actors.py`
poses actual body parts into the original ANM2 crop rectangles, timing and
attachment coordinates. `extras.py` covers props, panels and effects.
Existing authored Jangseung entity art is retained. `models/` holds GLB 2.0
exports with materials and normals, importable into Blender or another DCC.
`review.html` embeds the real models and native PNGs. Drag to orbit, pause,
select an item or download its GLB; model and PNG rotations share one angle.

The camera elevation stays fixed while each item turns around its upright
axis. Paper/coins have thin profiles, while containers and anatomy have
substantial sides. `items.json` records each camera pitch, axis and any
uniform inset required to keep the complete turn inside the 32×32 canvas.
The native preview frames are the actual runtime PNGs.

The actual tool is this repository's Python mesh builder/software rasterizer,
**not Blender, an installed art skill, or a trained image model**. GLB carries
PBR material parameters; review lighting is an approximation. `fidelity.py`
is the rejected silhouette-volume experiment. It and `auto.py`, `relief.py`,
`sculpt.py`, `entities.py` and old `notused` outputs are not production inputs.
`models.py` supplies the item inventory and standalone ANM2 export helper only.

## Isaac integration

Isaac consumes PNG/ANM2 rather than GLB. Item turntables contain 32 views,
32×32 pixels each, with one turn per 64 gameplay updates (about 2.13 seconds).
The native layer's crop advances through the strip; the pedestal, shadow,
animation state, tint and visibility remain native. Entities use model-rendered
sheets with the existing poses and timing, and do not spin.

`Config.aprilFools3D` / MCM → General → **April Fools 3D**:

- **Auto (April 1)**: enabled on the PC's local April 1; the saved value stays auto.
- **Always ON**: preview on any date.
- **OFF**: originals even on April 1.

This optional mode needs REPENTOGON's [Sprite layer inspection](https://repentogon.com/Sprite.html)
and [LayerState crop offset](https://repentogon.com/LayerState.html). When a
capability is unavailable, retain original art (or a static render when only
crop adjustment is unavailable). No whole-mod dependency change is made.
It substitutes only allowlisted **visible sheet paths**, never a hidden
pickup's subtype. Disable/exit/unload restores borrowed sheets/crops without
overwriting a later foreign replacement. World actors, pedestals, drops,
mod-rendered companions, grip overlays, evolution previews and effects are
covered. Additive flashes, shadows and light filaments too thin to form a
solid retain their original light imagery. Native HUD surfaces whose sprites the engine does not expose retain
their normal icons; there is no unsafe ItemConfig/global texture mutation.

`coverage.json` accounts for all 86 original PNGs under active `resources/gfx`:
76 have generated alternatives; 10 are fonts, transparent controls, a drawing
pixel/light falloff, or retired/template sheets. It is an **asset audit**, not
a claim that every engine-controlled HUD surface can be intercepted. Vanilla
referenced art and third-party assets are never copied or changed. Original
PNGs remain byte-for-byte intact. `_af3d.png` / `_af3d_spin.png` files ship;
models, review files and standalone ANM2 export templates in `isaac/` do not.

## Verification boundary

Automated tests cover the calendar, on/off precedence, missing APIs, a full
turn, pause behaviour, hidden/foreign sprite protection, morphs, restore and
unload, complete asset coverage, sheet sizes and clipping, and the pearl's
radius, ink visibility on slanted paper, outward/closed primitive geometry,
orthographic depth interpolation and independence of anatomy from painted brightness. These are offline checks. PNG/ANM2 changes require a **full game
restart**; a Lua reload is insufficient. No engine screenshot or visual pass
has been claimed for this set.

A live AR Glasses check on 2026-11-11 caught a wrapper-identity failure:
`Entity:GetSprite()` returned a distinct userdata each time, so treating it
as the ownership key accumulated the strip phase until the crop was millions
of pixels outside the 1024px sheet. Entity-owned baselines now use the live
entity identity and an EntityPtr. A post-fix observation across 192 live
updates saw all 32 phases, three wraparounds and zero crop mismatches.
This verifies runtime coordinates, not a captured visual pass. The regression
also reacquires wrappers twice per tick, runs garbage collection, checks
restoration/foreign replacement and removed-owner reuse.

After restart, check Auto/On/Off in MCM, a pedestal for a complete turn, a blind
pedestal and reroll, both sizes of the crab with 0/1/2 trinkets, ox walking in
each direction and sleeping, doors and custom effects. Check room/continue,
pause and exit. Run `conch_test locale` for the new menu strings. The user
performs these in-game actions; this project forbids UI automation.
