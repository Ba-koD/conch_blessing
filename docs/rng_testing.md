# RNG testing

How to measure the expected value of every random mechanic in the mod, and how to
extend the harness when a new one is added.

There are two tools and they check each other. Neither is sufficient alone:

| | `rng_report.py` | `conch_rng` console command |
| --- | --- | --- |
| Runs | Offline, no game needed | In game |
| Models | The Lua expressions, transcribed | Calls the shipped Lua functions |
| Constants | Parsed out of the Lua sources | Read from the live `data` tables |
| Catches | Constant drift, bad math, EID mismatches | Transcription errors in the report |
| Output | Markdown tables | Console + `log.txt` |

The report is a model. The probe is the real code. **Agreement between the two is the
result**; a number that only one of them produces has not been verified.

## Running the offline report

```bash
python rng_report.py                            # markdown to stdout
python rng_report.py --out docs/rng_report.md   # regenerate the committed report
python rng_report.py --samples 500000           # heavier Monte Carlo
python rng_report.py --seed 1234                # a different RNG stream
```

No dependencies beyond the standard library. `--samples` only affects the sampled
tables; closed-form figures are exact arithmetic and ignore it.

The generator reads every constant out of the Lua sources and **exits with an error
rather than defaulting** if one is missing, so renaming `minMultiplier` fails the run
instead of quietly publishing a stale number. Every figure in the output cites the
`file:line` it came from.

## Running the in-game probe

Open the console and type:

```
conch_rng              # every probe, 100000 samples
conch_rng 500000       # custom sample count
conch_rng luck 20      # evaluate the luck-scaled chances at Luck 20
```

Output goes to the console and to `log.txt`. `scripts/dev/rng_probe.lua` registers a
single `MC_EXECUTE_CMD` handler and touches no game state.

Some probes need a live run: `aMinus` reads the current player's split, and
`voidDagger` prints the live `MaxFireDelay`. Start a run before invoking it.

Any module that has not loaded prints `SKIPPED` instead of erroring, so a partial run
still reports whatever is available.

## How the probe reaches the real functions

The measured helpers are module-scope locals, so each item file exposes them through a
`_test` table used by nothing else:

| File | Exposed |
| --- | --- |
| `oral_steroids.lua`, `power_training.lua`, `injectable_steroids.lua` | `<module>.rollStat()` |
| `void_dagger.lua` | `getShotsPerSecond`, `computeProcChanceFromS`, `applyLuckBonus` |
| `soflam.lua` | `getProcChance` |
| `ice_breath.lua` / `fire_breath.lua` | `getFreezeChance` / `getBurnChance` |
| `time_money.lua` | `chooseCoinSubtype` |
| `a_minus.lua` | `computeRandomSplit` |

`rollStat` was hoisted from a per-call closure to a module function so the probe
measures the shipped expression instead of a copy. That also removed three duplicated
copies of the same roll.

## Adding a new mechanic

1. Keep the random part in a pure function at module scope: inputs in, number out, no
   game state. If it needs the player, take the player as an argument and read only
   fields a plain table can fake (`Luck`, `MaxFireDelay`).
2. Expose it on the module's `_test` table.
3. Add a probe function in `scripts/dev/rng_probe.lua` and call it from the command
   handler.
4. Add the matching section to `rng_report.py`, reading its constants with `const()`
   so the report follows the code.
5. Regenerate `docs/rng_report.md` and compare against `conch_rng` in game.

## Reading the numbers

- **Truncation.** `math.floor(x * 100) / 100` makes a continuous uniform discrete, so a
  `[0.8, 1.5)` roll averages `1.145`, not `1.15`. The mean is `(min + max - 0.01) / 2`.
- **Integer draws.** `math.random(1, 100) <= pct` truncates a fractional `pct`: at
  `3.75%` the real chance is `3%`. A sub-1% decay therefore does nothing until it
  crosses a whole percent.
- **Sequential `if/elseif` rolls** make each later branch conditional on the earlier
  ones failing, so configured percentages are inputs, not outcomes. `Time = Money`'s
  configured 5% nickel lands at 4.851%.
- **Additive stacking.** `SetItemAdditiveMultiplier` accumulates `value - 1` despite
  its name; StatsAPI applies `1 + cumulative`. A `total = total * roll` product
  somewhere in an item file is not necessarily what reaches the player - check where
  the value actually goes before trusting it.
- **Mean vs median.** Report both when a distribution is skewed. The mean of a
  skewed total is set by rare outliers; the median is closer to what a run feels like.

## Known findings

Recorded here because they are measurement results, not design decisions. None have
been changed.

1. **The per-item minimum never protects the applied value.** Each item's
   `math.max(minMultiplier, total)` sits in the dead product block. The live path
   clamps only at zero, so Injectable Steroids reaches a 0x multiplier - no damage at
   all - in roughly 1% of 3-to-5 stack runs.
2. **Power Training and Injectable Steroids roll a `speed` multiplier they never
   apply.** It is drawn, written to the run save and dropped. The separate
   `speedDecrease` path is configured to `0`, so it is a no-op too.
3. **The stat rolls use `math.random`, not `player:GetCollectibleRNG()`.** They are not
   seeded from the run, so a Glowing Hourglass rewind yields different values and
   multiplayer determinism is not guaranteed. `injectable_steroids.lua` builds a
   `combinedSeed` from the game seed and then never uses it.
4. **`injectablsteroids.data.currentInstantDeathPercent` is module-global**, so it is
   shared across players in co-op, and it lives outside SaveManager, so it resets on
   continue.
