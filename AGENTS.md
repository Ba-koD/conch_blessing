# AGENTS.md

## Project Overview

This repository is a The Binding of Isaac: Repentance/Rebirth mod named "Conch's Blessing".

Runtime load order starts at `main.lua`, then `scripts/conch_blessing_core.lua`, then the item registry in `scripts/conch_blessing_items.lua`. Item behavior usually lives under `scripts/items/collectibles`, `scripts/items/trinkets`, or `scripts/items/familiars`.

The mod depends on external runtime APIs:

- StatsAPI is required before the main mod initializes.
- Magic Conch is used by `scripts/conch_blessing_upgrade.lua`.
- Mod Config Menu integration is in `scripts/conch_blessing_mcm.lua`.
- EID descriptions and icons are generated from item data in `scripts/conch_blessing_items.lua` and `scripts/eid_language.lua`.

Core subsystem map:

- `scripts/callback_manager.lua` owns callback-key to `ModCallbacks` registration.
- `scripts/template.lua` owns upgrade morph visuals before/after item conversion.
- `scripts/conch_blessing_config.lua` owns language/debug/spawn settings.
- `scripts/conch_blessing_mcm.lua` owns MCM UI and setting persistence.
- `scripts/lib/stats.lua` owns unified stat multipliers/additions/cache display.

## Files To Treat Carefully

- `scripts/lib/isaacscript-common.lua` is vendored and very large. Do not edit it unless the task explicitly requires a vendor patch.
- `scripts/lib/save_manager.lua` and `scripts/lib/hidden_item_manager.lua` are shared support libraries. Prefer changing call sites first.
- `content/items.xml`, `content/itempools.xml`, `content/entities2.xml`, `content/gfx/death_items.anm2`, `content/gfx/death_items.png`, and `metadata.xml` are mod content data. If Lua item metadata or item sprites change, check whether `generate_xml.py` should regenerate generated content.
- Existing Korean text appears to contain mojibake in this checkout. Avoid touching translation strings unless the task is specifically about text or encoding.

## Code Style

- Keep Lua changes small and local to the item or subsystem being modified.
- Prefer existing patterns: add item definitions to `ConchBlessing.ItemData`, then register behavior through the `callbacks` table.
- Keep one global table per item namespace, for example `ConchBlessing.dragon` or `ConchBlessing.chronus`.
- Use `local` helpers and constants inside item files. Do not add globals unless they are part of the existing `ConchBlessing.*` API.
- Use `ConchBlessing.printDebug` for optional logs and `ConchBlessing.printError` for real failures. Avoid unconditional `Isaac.ConsoleOutput` in normal paths.

## Callback Guidelines

- Avoid adding `MC_POST_UPDATE`, `MC_POST_RENDER`, `MC_POST_PEFFECT_UPDATE`, or broad entity callbacks unless the item needs them continuously.
- If a broad callback is necessary, return early before expensive work. Check ownership, subtype, variant, or custom `GetData()` flags first.
- Prefer `ItemData.callbacks` plus `CallbackManager` over scattered direct `AddCallback` calls.
- Do not register empty callbacks through `ItemData.callbacks`.
- Cache static `ItemConfig` scans and repeated ID lists. Do not scan `CollectibleType.NUM_COLLECTIBLES` every frame.
- Avoid repeated `Isaac.GetRoomEntities()` or `Isaac.FindByType()` in per-entity update callbacks. Cache per-frame data or store runtime references when safe.
- Preserve multiplayer behavior by iterating `Game():GetNumPlayers()` when the effect can belong to any player.

## Stats, Config, And Debug

- Use `ConchBlessing.stats.unifiedMultipliers` for stat changes. Avoid raw stat overwrites unless the existing item pattern requires it.
- Respect tears SPS/MaxFireDelay conversion when changing fire-rate behavior.
- Minimize cache invalidations. Call `AddCacheFlags` and `EvaluateItems` only when state changes require recalculation.
- Use player/item-based RNG such as `InitSeed` or collectible RNG where deterministic behavior matters.
- Resolve language through `ConchBlessing_Config.GetCurrentLanguage`; MCM language changes should re-register EID descriptions when needed.
- Debug output should go through `ConchBlessing.printDebug`, `ConchBlessing.print`, or `ConchBlessing.printError`, include relevant player/item/cache context, and avoid hardcoded magic values.
- Upgrade visuals should use `Template.*.onBeforeChange` and `Template.*.onAfterChange` patterns; cosmetic effects should remain harmless.

## Save Data

- Use `ConchBlessing.SaveManager` for persistent and run-scoped state.
- Store persistent MCM/settings data under `SaveManager.GetSettingsSave().config` through the existing config helpers.
- Store serializable data only. Do not write entity, sprite, font, RNG, or userdata objects into saved tables.
- If runtime entity references are cached, clear them on room/game transitions and keep them out of SaveManager data.

## Generated Content

- After adding, removing, renaming, or changing metadata for items in `scripts/conch_blessing_items.lua`, run `python3 generate_xml.py` in a Python environment with Pillow to update `content/items.xml`, `content/itempools.xml`, `content/entities2.xml`, `content/gfx/death_items.anm2`, and `content/gfx/death_items.png`.
- After changing collectible or familiar item sprites under `resources/gfx/items/collectibles`, run `python3 generate_xml.py` in a Python environment with Pillow so generated death item spritesheets stay in sync.
- `content/gfx/death_items.png` generation requires Pillow. By default it preserves resized source icon colors. Use `--death-palette vanilla` to generate the vanilla death-screen color style (`RGB(54, 47, 45)` with alpha levels).
- Death item resizing defaults to trimming transparent source padding and fitting into the 16x16 death frame. Use `--death-resize raw_resize` for the original behavior: resize the full source image directly to 16x16 without trimming.

## Commit And Changelog Style

- Follow `https://git.intp.me/` for commit messages: `Type: English title` on the first line, one blank line, then Korean `- ` bullet body lines.
- Commit titles must use one of the allowed capitalized types from the guideline, keep the English title near 25-30 characters, and omit a trailing period.
- Commit body bullets must explain what and why in Korean, start with `- `, avoid blank lines between bullets, and end with a noun-style phrase such as `추가`, `수정`, `제거`, `전환`, `적용`, or `정리`.
- Steam Workshop changenotes should match the existing workshop style: one or more English typed summary lines such as `Fix: Fix EID Bug`, then a blank line, then short Korean summary lines without `-` bullets.
- Keep Steam changenotes concise and player-facing. Mention generated assets, upload automation, or tooling only when those changes affect the published mod package or release process.
- For the `Steam Workshop Publish` GitHub Actions workflow, paste release notes into the manual `changenote` input. Leaving it empty uploads only `Version <metadata.xml version>`.
- The Steam publish workflow should not generate or build mod content. It stages a copy of committed runtime files for SteamCMD; configure generated asset behavior in `generate_xml.py` defaults and commit generated files before publishing.

## Verification

- There is no normal automated Lua test suite for this mod.
- For Python generator changes, run `python3 -m py_compile generate_xml.py`.
- After changing generated-content rules, run `python3 generate_xml.py` in a Python environment with Pillow and inspect `content/gfx/death_items.png`.
- For Lua syntax checks, use the local Lua tooling only if available in the environment.
- For gameplay changes, verify in-game with debug mode off and then with debug mode on only when logs are needed.

## External Isaac Docs

- Use `ISAAC_DOCS_REFERENCE.md` for a quick map of which Wofsauge Isaac Docs pages to open for callbacks, entities, item XML, item pools, save data, rendering, and common enums.
- Prefer `https://wofsauge.github.io/IsaacDocs/rep/` pages. Treat `/abp/` and `oldDocs` search results as legacy references unless a task explicitly targets older API behavior.
