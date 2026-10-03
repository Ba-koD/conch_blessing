#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the expected-value report for every RNG mechanic in Conch's Blessing.

Constants are parsed out of the Lua sources rather than copied here, so the report
follows the code. A constant that cannot be found is a hard error: a silent default
would quietly publish a wrong number.

Usage
-----
    python rng_report.py                          # markdown to stdout
    python rng_report.py --out docs/rng_report.md # write to a file
    python rng_report.py --samples 500000         # heavier Monte Carlo
    python rng_report.py --seed 1234              # different RNG stream

The companion in-game probe (`conch_rng` from scripts/dev/rng_probe.lua) samples the
real Lua functions. This script models the same expressions offline, so agreement
between the two is the actual check.
"""
from __future__ import annotations

import argparse
import io
import math
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

SRC = {
    "oral": "scripts/items/collectibles/oral_steroids.lua",
    "power": "scripts/items/collectibles/power_training.lua",
    "inject": "scripts/items/collectibles/injectable_steroids.lua",
    "void": "scripts/items/collectibles/void_dagger.lua",
    "soflam": "scripts/items/collectibles/soflam.lua",
    "ice": "scripts/items/collectibles/ice_breath.lua",
    "fire": "scripts/items/collectibles/fire_breath.lua",
    "money": "scripts/items/familiars/time_money.lua",
    "aminus": "scripts/items/trinkets/a_minus.lua",
    "crown": "scripts/items/trinkets/angels_crown.lua",
    "chronus": "scripts/items/collectibles/chronus.lua",
    "liveeye": "scripts/items/collectibles/live_eye.lua",
}

_cache: dict[str, list[str]] = {}


def lines(key: str) -> list[str]:
    if key not in _cache:
        path = os.path.join(ROOT, SRC[key])
        with io.open(path, encoding="utf-8", errors="replace") as f:
            _cache[key] = f.read().splitlines()
    return _cache[key]


def const(key: str, name: str) -> tuple[float, str]:
    """Return (value, "file:line") for `name = <number>` in a Lua source."""
    pattern = re.compile(r"^\s*(?:local\s+)?" + re.escape(name) + r"\s*=\s*(-?[\d.]+)\s*,?")
    hits = [(float(m.group(1)), i + 1) for i, ln in enumerate(lines(key))
            if (m := pattern.match(ln))]
    if not hits:
        sys.exit(f"ERROR: constant {name!r} not found in {SRC[key]}")
    value, line_no = hits[0]
    return value, f"`{SRC[key]}:{line_no}`"


def rolled_stats(key: str) -> list[str]:
    """Stat fields assigned from rollStat() in the item's roll table."""
    return re.findall(r"^\s*(\w+)\s*=\s*rollStat\(\)", "\n".join(lines(key)), re.M)


def applied_stats(key: str) -> list[str]:
    """Stat names actually handed to StatsAPI."""
    found = re.findall(r'SetItemAdditiveMultiplier\(\s*player\s*,\s*\w+\s*,\s*"(\w+)"',
                       "\n".join(lines(key)))
    out = []
    for name in found:
        if name not in out:
            out.append(name)
    return out


def cite(key: str, needle: str) -> str:
    for i, ln in enumerate(lines(key)):
        if needle in ln:
            return f"`{SRC[key]}:{i + 1}`"
    sys.exit(f"ERROR: snippet {needle!r} not found in {SRC[key]}")


def const_table(key: str, name: str) -> list[tuple[str, float, str]]:
    """Return [(entry, value, "file:line")] for `local name = { [X.ENTRY] = n, ... }`."""
    src_lines = lines(key)
    start = next((i for i, ln in enumerate(src_lines)
                  if re.match(r"^\s*(?:local\s+)?" + re.escape(name) + r"\s*=\s*\{", ln)), None)
    if start is None:
        sys.exit(f"ERROR: table {name!r} not found in {SRC[key]}")
    rows = []
    for i in range(start + 1, len(src_lines)):
        ln = src_lines[i]
        if re.match(r"^\s*\}", ln):
            break
        m = re.match(r"^\s*\[[\w.]*?(\w+)\]\s*=\s*(-?[\d.]+)\s*,?", ln)
        if m:
            rows.append((m.group(1), float(m.group(2)), f"`{SRC[key]}:{i + 1}`"))
    if not rows:
        sys.exit(f"ERROR: table {name!r} in {SRC[key]} has no numeric entries")
    return rows


def const_list(key: str, name: str) -> tuple[list[str], str]:
    """Return ([entry, ...], "file:line") for `local name = { X.ENTRY, ... }`."""
    src_lines = lines(key)
    start = next((i for i, ln in enumerate(src_lines)
                  if re.match(r"^\s*(?:local\s+)?" + re.escape(name) + r"\s*=\s*\{", ln)), None)
    if start is None:
        sys.exit(f"ERROR: list {name!r} not found in {SRC[key]}")
    entries = []
    for ln in src_lines[start + 1:]:
        if re.match(r"^\s*\}", ln):
            break
        m = re.match(r"^\s*[\w.]*?(\w+)\s*,?\s*(?:--.*)?$", ln)
        if m:
            entries.append(m.group(1))
    if not entries:
        sys.exit(f"ERROR: list {name!r} in {SRC[key]} has no entries")
    return entries, f"`{SRC[key]}:{start + 1}`"


def pick_random_copies(copies: list, count: int, randint) -> list:
    """Transcribes chronus.lua pickRandomCopies: a partial Fisher-Yates shuffle,
    randint(n) returning 0..n-1 like RNG:RandomInt."""
    work = list(copies)
    n = len(work)
    picked = []
    for i in range(1, min(max(0, count), n) + 1):
        j = i + randint(n - i + 1)
        work[i - 1], work[j - 1] = work[j - 1], work[i - 1]
        picked.append(work[i - 1])
    return picked


# --------------------------------------------------------------------------- model
def roll_stat(lo: float, hi: float, rng: random.Random) -> float:
    """math.floor((math.random() * span + MIN) * 100) / 100"""
    return math.floor((rng.random() * (hi - lo) + lo) * 100) / 100


def roll_mean(lo: float, hi: float) -> float:
    """Truncating a continuous uniform to 2dp yields a discrete uniform over
    {lo, lo+0.01, ..., hi-0.01}, whose mean is (lo + hi - 0.01)/2."""
    return (lo + hi - 0.01) / 2


def table(headers: list[str], rows: list[list[str]]) -> list[str]:
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join("---" for _ in headers) + "|"]
    out += ["| " + " | ".join(r) + " |" for r in rows]
    return out


_LO_HI = {
    "oral": ("MIN_MULTIPLIER", "MAX_MULTIPLIER"),
    "power": ("minMultiplier", "maxMultiplier"),
    "inject": ("minMultiplier", "maxMultiplier"),
}


_FACTOR = {
    "oral": "MIN_TOTAL_MULTIPLIER_FACTOR",
    "power": "minTotalMultiplierFactor",
    "inject": "minTotalMultiplierFactor",
}


def factor_name_of(key: str) -> str:
    return _FACTOR[key]


def lo_name_of(key: str) -> str:
    return _LO_HI[key][0]


def hi_name_of(key: str) -> str:
    return _LO_HI[key][1]


# -------------------------------------------------------------------------- report
def build(samples: int, seed: int) -> str:
    rng = random.Random(seed)
    md: list[str] = []
    w = md.append

    w("# Conch's Blessing - RNG expected values")
    w("")
    w(f"Generated by `rng_report.py` (seed {seed}). Constants are read from the Lua")
    w("sources at generation time; every figure cites the line it came from.")
    w("")
    w("Closed-form results are exact arithmetic and use no sampling. Only the")
    w(f"distribution tables are sampled, at {samples:,} draws each.")
    w("")

    rollers = [
        ("Oral Steroids", "oral", "MIN_MULTIPLIER", "MAX_MULTIPLIER", "on pickup", 4),
        ("Power Training", "power", "minMultiplier", "maxMultiplier", "on use", 5),
        ("Injectable Steroids", "inject", "minMultiplier", "maxMultiplier", "on use", 5),
    ]

    # 1 --------------------------------------------------------------------------
    w("## 1. Per-roll stat multiplier")
    w("")
    w("`value = math.floor((math.random() * span + MIN) * 100) / 100`")
    w("")
    w("Truncation to 2 decimals makes this a discrete uniform, so the mean is")
    w("`(min + max - 0.01) / 2` - a hundredth below the midpoint, not the midpoint.")
    w("")
    rows = []
    for label, key, lo_name, hi_name, trigger, nstats in rollers:
        lo, lo_cite = const(key, lo_name)
        hi, _ = const(key, hi_name)
        mc = sum(roll_stat(lo, hi, rng) for _ in range(samples)) / samples
        rows.append([label, f"{lo} - {hi}", trigger, str(nstats),
                     f"**{roll_mean(lo, hi):.4f}**", f"{mc:.4f}", lo_cite])
    w("\n".join(table(
        ["Item", "Range", "Trigger", "Stats rolled", "Exact E per stat", "Measured", "Source"],
        rows)))
    w("")
    w("### Per-stat coverage")
    w("")
    w("Every stat is an independent draw from the same distribution, so each one has the")
    w("same expected value. What differs per item is which rolled stats reach the player.")
    w("")
    audit = []
    for label, key, _, _, _, _ in rollers:
        rolled = rolled_stats(key)
        applied = {a.lower() for a in applied_stats(key)}
        for stat in rolled:
            live = stat.lower() in applied
            audit.append([label, stat, "yes" if live else "**no**",
                          f"{roll_mean(*(const(key, n)[0] for n in (lo_name_of(key), hi_name_of(key)))):.4f}"
                          if live else "-"])
    w("\n".join(table(["Item", "Rolled stat", "Applied?", "E if applied"], audit)))
    w("")
    dead = [(i, st) for i, st, ok, _ in audit if ok != "yes"]
    if dead:
        w("A rolled stat marked **no** is drawn, stored in the run save and then never")
        w("registered with StatsAPI. It still consumes an RNG draw and still shows up in")
        w("save data, so it reads as an active bonus that does nothing:")
        w("")
        for item, stat in dead:
            w(f"- **{item}** rolls `{stat}` and never applies it.")
        w("")

    # 2 --------------------------------------------------------------------------
    w("## 2. Stacking")
    w("")
    w("Rolls are registered one per stack with `SetItemAdditiveMultiplier`")
    w(f"({cite('oral', 'um:SetItemAdditiveMultiplier(player, ORAL_STEROIDS_ID')}).")
    w("Despite the name that call accumulates: StatsAPI stores `cumulative += value - 1`")
    w("and applies `effectiveM = 1 + cumulative`. So the applied total is")
    w("")
    w("    total = 1 + sum(m_i - 1)")
    w("")
    w("which is additive, matching the EID text.")
    w("")
    w("> The `totalDamage = totalDamage * m` product in each item file is **dead**: it is")
    w("> computed, clamped to the per-item minimum, formatted into a debug log and then")
    w("> discarded. Nothing reads it; the applied floor below is what protects the")
    w("> value.")
    w("")
    depths = [1, 2, 3, 5, 10]
    per_depth = max(1000, samples // 2)
    for label, key, lo_name, hi_name, _, _ in rollers:
        lo, _ = const(key, lo_name)
        hi, _ = const(key, hi_name)
        exact_roll = roll_mean(lo, hi)
        factor, factor_cite = const(key, factor_name_of(key))
        floor_value = lo * factor
        rows = []
        for n in depths:
            totals = []
            for _ in range(per_depth):
                total = 1.0
                for _ in range(n):
                    total += roll_stat(lo, hi, rng) - 1.0
                totals.append(max(floor_value, total))
            totals.sort()
            rows.append([
                f"x{n}",
                f"**{1 + n * (exact_roll - 1):.3f}**",
                f"{sum(totals) / len(totals):.3f}",
                f"{totals[len(totals) // 2]:.3f}",
                f"{sum(1 for t in totals if t < 1.0) / len(totals):.1%}",
                f"{sum(1 for t in totals if t <= floor_value) / len(totals):.1%}",
            ])
        w(f"### {label} (roll {lo} - {hi}, E per roll {exact_roll:.3f})")
        w("")
        w(f"Applied total is floored at `{lo:g} * {factor:g}` = **{floor_value:g}** ({factor_cite}).")
        w("")
        w("\n".join(table(
            ["Stacks", "Exact E", "Measured", "Median", "P(total < 1)", "P(at floor)"], rows)))
        w("")
        worst = 1 + depths[-1] * (lo - 1)
        w(f"Unfloored worst case at x{depths[-1]} would be `1 + 10*({lo} - 1)` = {worst:g}; "
          f"the floor holds it at {floor_value:g}.")
        w("")

    # 3 --------------------------------------------------------------------------
    base_pct, base_cite = const("inject", "baseInstantDeathPercent")
    inc_pct, _ = const("inject", "instantDeathPercentIncrement")
    red, red_cite = const("inject", "reductionAmount")
    w("## 3. Injectable Steroids - instant death")
    w("")
    w(f"`math.random(1,100) <= pct` ({cite('inject', 'local deathRoll')}), where")
    w(f"`pct = {base_pct:g} + {inc_pct:g} * usesThisFloor` ({base_cite}), reset per floor and")
    w(f"reduced {red:g} per room clear, floored at the base ({red_cite}).")
    w("")
    w(f"The draw is an integer 1-100, so a fractional chance truncates: the {red:g}")
    w("per-room-clear decay changes nothing until it crosses a whole percent.")
    w("")
    rows, survive, exp_uses, certain = [], 1.0, 0.0, None
    for k in range(1, 1000):
        pct = min(100.0, base_pct + inc_pct * (k - 1))
        effective = math.floor(pct) / 100  # math.random(1,100) <= pct
        exp_uses += survive
        if k <= 10:
            rows.append([str(k), f"{pct:g}%", f"{effective:.0%}",
                         f"{survive * effective:.2%}",
                         f"{1 - survive * (1 - effective):.2%}"])
        survive *= 1 - effective
        if certain is None and pct >= 100:
            certain = k
        if survive <= 0.0:
            break
    w("\n".join(table(
        ["Use #", "Raw pct", "Effective", "P(die here)", "Cumulative P(dead)"], rows)))
    w("")
    w(f"- Death becomes certain on use **{certain}** (the chance reaches 100%).")
    w(f"- Expected uses per floor before dying: **{exp_uses:.2f}** (ignoring room-clear decay).")
    w("")

    # 4 --------------------------------------------------------------------------
    w("## 4. Void Dagger proc chance")
    w("")
    w(f"`S = max(1, 30/(MaxFireDelay+1))`, `p = clamp((30-S)/100, 0.05, 1.0)`, then")
    w(f"`final = min(1.0, p * (1 + 0.1*Luck))` ({cite('void', 'local function computeProcChanceFromS')}).")
    w("Faster fire rate *lowers* the chance, down to the 5% floor.")
    w("")
    lucks = [0, 5, 10, 20]
    rows = []
    for d in (0, 1, 2, 3, 5, 7, 10, 15, 20):
        s = max(1.0, 30.0 / (d + 1.0))
        base = min(1.0, max(0.05, (30.0 - s) / 100.0))
        rows.append([str(d), f"{s:.2f}", f"{base:.1%}"] +
                    [f"{min(1.0, base * (1 + 0.1 * L)):.1%}" for L in lucks])
    w("\n".join(table(["MaxFireDelay", "Shots/s", "Base"] +
                      [f"Luck {L}" for L in lucks], rows)))
    w("")

    # 5 --------------------------------------------------------------------------
    sof_base, sof_cite = const("soflam", "baseProcPercent")
    sof_luck, _ = const("soflam", "luckProcPerPoint")
    w("## 5. Flat luck-scaled chances")
    w("")
    w(f"- SOFLAM target: `clamp({sof_base:g} + {sof_luck:g}*Luck, 0, 100)%` ({sof_cite})")
    w(f"- Ice Breath freeze: `clamp(Luck, 0, 100)%` ({cite('ice', 'local function getFreezeChance')})")
    w(f"- Fire Breath burn: `clamp(Luck*5, 0, 100)%` ({cite('fire', 'local function getBurnChance')})")
    w("")
    rows = []
    for L in (-5, 0, 1, 5, 10, 18, 20, 50, 100):
        rows.append([str(L),
                     f"{min(100, max(0, sof_base + sof_luck * L)):g}%",
                     f"{min(100, max(0, L)):g}%",
                     f"{min(100, max(0, L * 5)):g}%"])
    w("\n".join(table(["Luck", "SOFLAM", "Ice freeze", "Fire burn"], rows)))
    w("")
    w(f"Saturation points: SOFLAM at Luck {math.ceil((100 - sof_base) / sof_luck):g}, "
      "Fire Breath at Luck 20, Ice Breath at Luck 100.")
    w("")

    # 6 --------------------------------------------------------------------------
    w("## 6. Time = Money coin replacement")
    w("")
    w(f"The rolls are a sequential `if/elseif` ({cite('money', 'if rng:RandomFloat() < dimeP')}),")
    w("so each tier is conditional on the earlier ones failing. The configured")
    w("percentages are therefore inputs, not outcomes.")
    w("")
    tiers = [("dime", "probDime", 10), ("golden", "probGolden", 1),
             ("nickel", "probNickel", 5), ("lucky", "probLucky", 1)]
    per_point, _ = const("money", "luckMultiplierPerPoint")
    cap, cap_cite = const("money", "luckMultiplierCap")
    base_p = {name: const("money", key)[0] for name, key, _ in tiers}
    for L in (0, 5, 10, 30):
        mult = min(cap, max(1.0, 1 + per_point * L))
        remain, rows, ev = 1.0, [], 0.0
        for name, _, value in tiers:
            p = remain * base_p[name] * mult
            remain *= 1 - base_p[name] * mult
            ev += p * value
            rows.append([name, f"{base_p[name]:.0%}", f"**{p:.3%}**"])
        ev += remain * 1
        rows.append(["penny", "-", f"{remain:.3%}"])
        w(f"### Luck {L} (multiplier x{mult:g}, capped at x{cap:g} - {cap_cite})")
        w("")
        w("\n".join(table(["Coin", "Configured", "Actual"], rows)))
        w("")
        w(f"Expected value per dropped coin: **{ev:.4f}**")
        w("")

    # 7 --------------------------------------------------------------------------
    total_sum, sum_cite = const("aminus", "totalMultSum")
    min_per, _ = const("aminus", "minPerStat")
    stats = re.search(r"stats\s*=\s*\{([^}]*)\}", "\n".join(lines("aminus")))
    names = re.findall(r'"([^"]+)"', stats.group(1)) if stats else []
    if not names:
        sys.exit("ERROR: could not parse a_minus stats list")
    k = len(names)
    w("## 7. A- stat split")
    w("")
    w(f"{k} uniform weights are normalised and scale the budget left after the per-stat")
    w(f"minimum: `stat = {min_per:g} + w_i/sum(w) * ({total_sum:g} - {k}*{min_per:g})` ({sum_cite}).")
    w("By symmetry each share averages `1/{0}`, so every stat has the same mean.".format(k))
    w("")
    samples_a = {i: [] for i in range(k)}
    for _ in range(samples):
        weights = [max(1e-6, rng.random()) for _ in range(k)]
        s = sum(weights)
        for i in range(k):
            samples_a[i].append(min_per + weights[i] / s * (total_sum - min_per * k))
    exact = min_per + (total_sum - min_per * k) / k
    rows = []
    for i, name in enumerate(names):
        v = sorted(samples_a[i])
        rows.append([name, f"**{exact:.4f}**", f"{sum(v) / len(v):.4f}",
                     f"{v[len(v) // 2]:.3f}", f"{min(v):.3f} - {max(v):.3f}"])
    w("\n".join(table(["Stat", "Exact E", "Measured", "Median", "Observed range"], rows)))
    w("")
    w(f"The sum is always exactly {total_sum:g}; the per-stat bound is "
      f"[{min_per:g}, {min_per + total_sum - min_per * k:g}].")
    w("")

    # 8 --------------------------------------------------------------------------
    one_mod, one_cite = const("crown", "blessedChanceGolden")
    both_mod, both_cite = const("crown", "blessedChanceBoth")
    w("## 8. Angel's Crown blessed Treasure Room")
    w("")
    w("One roll per converted Treasure Room, seeded from the room's `SpawnSeed` so a")
    w("re-entry cannot reroll it. The draw is a bare comparison against a flat chance")
    w(f"({cite('crown', 'return rng:RandomFloat() < chance')}) and `RandomFloat()` is")
    w("uniform on `[0, 1)`, so the effective odds equal the configured ones: there is no")
    w("truncation and no sequential-branch loss here.")
    w("")
    w(f"- one modifier (golden trinket **or** Mom's Box): {one_mod:.0%} ({one_cite})")
    w(f"- both modifiers: {both_mod:.0%} ({both_cite})")
    w("")
    rows = []
    for label, chance in (("plain", 0.0), ("Mom's Box", one_mod),
                          ("golden", one_mod), ("golden + Mom's Box", both_mod)):
        hits = sum(1 for _ in range(samples) if rng.random() < chance)
        rows.append([label, f"**{chance:.1%}**", f"{hits / samples:.3%}"])
    w("\n".join(table(["Holder state", "Exact P", "Measured"], rows)))
    w("")
    w("Rooms roll independently, so over `n` converted Treasure Rooms the chance of at")
    w("least one blessing is `1 - (1 - p)^n`:")
    w("")
    rows = []
    for n in (1, 2, 3, 5, 8):
        rows.append([str(n),
                     f"{1 - (1 - one_mod) ** n:.1%}",
                     f"{1 - (1 - both_mod) ** n:.1%}"])
    w("\n".join(table(["Treasure Rooms", "one modifier", "both"], rows)))
    w("")

    # 9 --------------------------------------------------------------------------
    block = const_table("chronus", "PROJECTILE_BLOCK_PERCENT")
    per_stack, per_stack_cite = const("chronus", "SPAWN_CHANCE_PER_STACK")
    w("## 9. Chronus projectile block and blue fly / spider spawns")
    w("")
    w("Absorbed barrier familiars add a flat percentage per absorbed copy to one chance")
    w("of ignoring an enemy projectile hit, capped at 100% "
      f"({cite('chronus', 'return math.min(1, percent / 100)')}). The roll is")
    w("`RandomFloat() < chance` on the Chronus collectible RNG, uniform on `[0, 1)`, so the")
    w("effective odds equal the configured sum.")
    w("")
    rows = [[entry.replace("COLLECTIBLE_", ""), f"{value:g}%", where] for entry, value, where in block]
    w("\n".join(table(["Familiar", "Per copy", "Source"], rows)))
    w("")
    every_once = sum(v for _, v, _ in block)
    w(f"One copy of every listed familiar adds up to **{every_once:g}%**.")
    w("")
    rows = []
    for label, pct in (("one 1% familiar", 1.0), ("Sworn Protector + Psy Fly", 10.0),
                       ("every listed familiar once", every_once)):
        p = min(1.0, pct / 100)
        hits = sum(1 for _ in range(samples) if rng.random() < p)
        rows.append([label, f"**{p:.1%}**", f"{hits / samples:.3%}"])
    w("\n".join(table(["Absorbed", "Exact P", "Measured"], rows)))
    w("")
    w(f"Blue fly (Rotten Baby, 7 Seals) and blue spider (Juicy Sack, Sissy Longlegs) spawns")
    w(f"add {per_stack:.0%} per absorbed copy ({per_stack_cite}), capped at 100%. Each")
    w("physical attack claims one roll before the RNG, so a piercing tear or a beam rolls")
    w("once across all of its targets, and a familiar body (the spawned flies and spiders")
    w("themselves) cannot claim one.")
    w("")
    rows = []
    for stacks in (1, 2, 3):
        p = min(1.0, per_stack * stacks)
        hits = sum(1 for _ in range(samples) if rng.random() < p)
        rows.append([str(stacks), f"**{p:.0%}**", f"{hits / samples:.3%}"])
    w("\n".join(table(["Absorbed copies", "Exact P per attack", "Measured"], rows)))
    w("")

    # 10 -------------------------------------------------------------------------
    procs = const_table("chronus", "PROC_CHANCE_PERCENT")
    intervals = const_table("chronus", "CLEAR_REWARD_INTERVAL")
    paschal, paschal_cite = const("chronus", "PASCHAL_TEARS_PER_CLEAR")
    effects, effects_cite = const_list("chronus", "FLOOR_PICK_EFFECTS")
    w("## 10. Chronus chance effects, room-clear drops, GB Bug and floor picks")
    w("")
    w("Each chance effect adds its percentage per absorbed copy, capped at 100% "
      f"({cite('chronus', 'return math.min(1, stacked / 100)')}), rolled as")
    w("`RandomFloat() < chance` on the familiar's own collectible RNG. Attack procs claim one")
    w("roll per physical attack before the RNG; room-clear drops roll once per cleared room;")
    w("Dry Baby rolls once per hit taken.")
    w("")
    rows = []
    for entry, pct, where in procs:
        p1 = min(1.0, pct / 100)
        hits = sum(1 for _ in range(samples) if rng.random() < p1)
        rows.append([entry.replace("COLLECTIBLE_", ""), f"{pct:g}%", f"**{p1:.0%}**",
                     f"{hits / samples:.3%}", f"{min(1.0, 2 * pct / 100):.0%}",
                     f"{min(1.0, 3 * pct / 100):.0%}", where])
    w("\n".join(table(["Familiar", "Per copy", "1 copy", "Measured", "2 copies", "3 copies", "Source"], rows)))
    w("")
    w("Counter drops are not random: each cleared room advances a saved counter, and every")
    w("absorbed copy adds one drop when it reaches the interval.")
    w("")
    rows = [[entry.replace("COLLECTIBLE_", ""), f"{value:g}", f"{1 / value:.3f}", where]
            for entry, value, where in intervals]
    w("\n".join(table(["Familiar", "Rooms per drop", "Drops per room per copy", "Source"], rows)))
    w("")
    w(f"Paschal Candle adds {paschal:g} tears per copy for every room clear, uncapped "
      f"({paschal_cite}); it is stored as whole hundredths, so it never drifts.")
    w("")
    n_copies, n_pick = 6, 3
    counts = [0] * n_copies
    trials = max(1, samples // 4)
    for _ in range(trials):
        for idx in pick_random_copies(list(range(n_copies)), n_pick, lambda k: rng.randrange(k)):
            counts[idx] += 1
    spread = max(counts) / trials - min(counts) / trials
    w("GB Bug hands back `floor(N / 2)` of the `N` other absorbed copies, chosen without")
    w(f"replacement by a partial Fisher-Yates shuffle ({cite('chronus', 'local j = i + randomInt(n - i + 1)')}),")
    w(f"so each copy returns with probability `floor(N/2) / N`. With N = {n_copies} every copy")
    w(f"should return {n_pick / n_copies:.0%} of the time; over {trials} trials the per-copy rate")
    w(f"ranges {min(counts) / trials:.3%} to {max(counts) / trials:.3%} (spread {spread:.3%}).")
    w("")
    block_entries = [entry for entry, _, _ in const_table("chronus", "PROJECTILE_BLOCK_PERCENT")]
    pool = sorted(set(effects) | set(block_entries))
    w(f"Buddy in a Box / Lil Delirium draw one familiar per copy and floor, with replacement,")
    w(f"uniformly from {len(pool)} candidates: the {len(effects)} effect familiars in")
    w(f"`FLOOR_PICK_EFFECTS` ({effects_cite}) plus the {len(block_entries)} projectile-block familiars,")
    w(f"each at **{1 / len(pool):.3%}** per pick.")
    w("")
    pretty, pretty_cite = const("chronus", "PRETTY_FLY_BLOCK_PERCENT")
    altar, altar_cite = const("chronus", "ALTAR_MAX_SACRIFICES")
    w("Temporary familiars reuse the same draws. A Pretty Fly pill fly absorbed under")
    w(f"REPENTOGON adds **{pretty:g}%** to the projectile block above ({pretty_cite}). When The Twins")
    w("duplicates, it picks one absorbed effect familiar uniformly with its trinket RNG. Sacrificial")
    w(f"Altar takes up to {altar:g} copies ({altar_cite}), owned familiars first and the rest from the")
    w("absorbed pool through the same partial Fisher-Yates draw as GB Bug.")
    w("")

    # 11 -------------------------------------------------------------------------
    base, base_cite = const("liveeye", "missForgiveBaseChance")
    per_luck, per_luck_cite = const("liveeye", "missForgiveLuckBonus")
    w("## 11. Live Eye miss forgiveness")
    w("")
    w(f"A tear that misses lowers the damage multiplier unless a roll forgives it: base {base:.0%}")
    w(f"({base_cite}) plus {per_luck:.0%} per point of luck ({per_luck_cite}), clamped to `[0, 1]`")
    w(f"({cite('liveeye', 'return math.max(0, math.min(1, chance))')}). The roll is `RandomFloat() < chance` on")
    w("the Live Eye collectible RNG of the tear's owner, so the effective odds equal the formula.")
    w("")
    rows = []
    for luck in (-10, -5, -2, 0, 1, 3, 5, 8, 10, 15):
        p = max(0.0, min(1.0, base + per_luck * luck))
        hits = sum(1 for _ in range(samples) if rng.random() < p)
        rows.append([str(luck), f"**{p:.0%}**", f"{hits / samples:.3%}"])
    w("\n".join(table(["Luck", "Exact P (no loss)", "Measured"], rows)))
    w("")

    return "\n".join(md) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--samples", type=int, default=200000,
                    help="Monte Carlo draws per sampled table (default: 200000)")
    ap.add_argument("--seed", type=int, default=20260903, help="RNG seed for reproducibility")
    ap.add_argument("--out", help="write markdown here instead of stdout")
    args = ap.parse_args()

    report = build(args.samples, args.seed)
    if args.out:
        path = args.out if os.path.isabs(args.out) else os.path.join(ROOT, args.out)
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(report)
        print(f"wrote {path} ({len(report.splitlines())} lines)")
    else:
        sys.stdout.write(report)


if __name__ == "__main__":
    main()
