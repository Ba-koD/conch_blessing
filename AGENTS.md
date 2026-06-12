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
- Keep `ConchBlessing.ItemData` grouped in this order: collectible items (`passive` and `active`) first, familiar items second, trinkets last. Append new items to the end of their group because generated `content/items.xml` IDs follow this registry order.
- Keep one global table per item namespace, for example `ConchBlessing.dragon` or `ConchBlessing.chronus`.
- Use `local` helpers and constants inside item files. Do not add globals unless they are part of the existing `ConchBlessing.*` API.
- Use `ConchBlessing.printDebug` for optional logs and `ConchBlessing.printError` for real failures. Avoid unconditional `Isaac.ConsoleOutput` in normal paths.

## Item Sprite Style

- Treat item icons as native 32x32 pixel art. If an AI or high-resolution draft is used, always finish with direct 32x32 cleanup; do not rely on automatic downscaling for final edges, layer order, or readability.
- For style references, prefer vanilla Isaac collectible sprites from `extracted_resources/resources/gfx/items/collectibles` and high-quality local mod references such as Epiphany, Astrobirth, and Auri only for general production traits. Do not copy, trace, or recreate another mod's specific item artwork.
- Match the common Isaac item language: compact readable silhouette, slightly handmade asymmetry, transparent corners, near-black 1-2 px outline, top-left lighting, muted grimy shadow colors, and small clusters of bright highlight pixels.
- Keep each material on a limited palette. A good default is outline, dark shadow, midtone, and one sparse highlight; use extra highlight colors only for the focal point.
- Avoid muddy antialiasing, soft gradients, airbrushed glow, photorealistic detail, and thin hairline elements that disappear at 32px. Favor hard pixel clusters and clear shape separation.
- Check layer order manually after scaling or cleanup. Foreground tools, blades, handles, knots, and cut points should visibly overlap in the intended order at 32px.
- For AI sprite prompts, specify final native 32x32 readability, hard pixel edges, limited palette, transparent padding, no text/UI/frame/pedestal, and "reference style traits only, no copying" when using vanilla or mod art as inspiration.

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

- After creating an item or adding, removing, renaming, or changing metadata for items in `scripts/conch_blessing_items.lua`, run `uv run generate_xml` once to update `content/items.xml`, `content/itempools.xml`, `content/entities2.xml`, `content/gfx/death_items.anm2`, and `content/gfx/death_items.png`. If `uv` is unavailable, use `python3 generate_xml.py` in a Python environment with Pillow.
- After changing collectible or familiar item sprites under `resources/gfx/items/collectibles`, run `python3 generate_xml.py` in a Python environment with Pillow so generated death item spritesheets stay in sync.
- `content/gfx/death_items.png` generation requires Pillow. By default it preserves resized source icon colors. Use `--death-palette vanilla` to generate the vanilla death-screen color style (`RGB(54, 47, 45)` with alpha levels).
- Death item resizing defaults to trimming transparent source padding and fitting into the 16x16 death frame. Use `--death-resize raw_resize` for the original behavior: resize the full source image directly to 16x16 without trimming.
- Local git hooks live in `.githooks`; enable them with `git config core.hooksPath .githooks`. The `pre-push` hook runs `python3 generate_xml.py`; it amends only generated content files into `HEAD` when they changed, then stops that push so the same push command can be run again with the amended commit. The local `python3` environment must have Pillow installed.

## Commit And Changelog Style

- Follow `https://git.intp.me/` for commit messages: `Type: English title` on the first line, one blank line, then Korean `- ` bullet body lines.
- Commit titles must use one of the allowed capitalized types from the guideline, keep the English title near 25-30 characters, and omit a trailing period.
- Commit body bullets must explain what and why in Korean, start with `- `, avoid blank lines between bullets, and end with a noun-style phrase such as `추가`, `수정`, `제거`, `전환`, `적용`, or `정리`.
- Before any `dev` to `main` merge, push, or release-version decision, run `git fetch origin` and compare against `origin/main` and `origin/dev`. Do not decide from stale local branch state.
- Do not change `metadata.xml` versions during `dev` to `main` merges, release-merge requests, pushes, or ordinary dev commits unless the user explicitly requests a version change.
- When preparing a `dev` to `main` merge, compare `metadata.xml` versions on fetched `origin/main`, `origin/dev`, and the branch being merged. Do not manually bump versions for the merge; let the Steam publish workflow resolve the publish version unless the user explicitly requests a specific version change.
- The Steam publish workflow has an optional manual `version` input. A manual `version` greater than the downloaded Steam Workshop version is used as the publish version, even when it differs from committed `metadata.xml`.
- If a manual workflow `version` is equal to or lower than the downloaded Steam Workshop version, ignore that input and use the empty-version automatic resolution path.
- With empty `version`, the Steam publish workflow downloads the current Steam Workshop item, compares its `metadata.xml` version with the committed version, and stages the committed version only when the committed version is greater than the Workshop version.
- With empty `version`, if committed `metadata.xml` is equal to or lower than the downloaded Steam Workshop version, stage and upload the next patch version after the downloaded Workshop version.
- The Steam publish workflow may edit `metadata.xml` in the workflow workspace before staging the upload package, but it must commit and push that resolved version only after SteamCMD upload succeeds.
- Steam Workshop changenotes should match the existing workshop style: one or more English typed summary lines such as `Fix: Fix EID Bug`, then a blank line, then short Korean summary lines without `-` bullets.
- Keep Steam changenotes concise and player-facing. Mention generated assets, upload automation, or tooling only when those changes affect the published mod package or release process.
- When asked to prepare a `dev` to `main` merge request or release-merge request, include a Steam Workshop changenote draft in the response. Provide the GitHub Actions-ready `changenote` value with literal `\n` line breaks so it can be pasted directly into the manual workflow input.
- When asked for a changelog draft, either return the text directly in chat or create it under the ignored `.tmp/` directory. Do not leave changelog drafts as tracked files unless the user explicitly requests that.
- For the `Steam Workshop Publish` GitHub Actions workflow, paste release notes into the manual `changenote` input. Use literal `\n` for line breaks. Leaving it empty uploads only `Version <resolved metadata.xml version>`.
- The Steam publish workflow should not generate or build mod content. When run on `main`, it stages a copy of committed runtime files on the self-hosted runner and uploads it through SteamCMD. Configure generated asset behavior in `generate_xml.py` defaults and commit generated files before publishing.
- SteamCMD `workshop_build_item` must run once per publish with a single English base VDF. Do not upload separate `english` and `koreana` VDF files; SteamCMD can overwrite the default title/description with the last VDF instead of creating localized fields.
- Workshop title and description localization must be maintained in the Steam Workshop web UI. General Steam Web API keys return `401 Unauthorized` for Workshop localization updates on this item, and this repo does not have Isaac publisher Web API authority.
- Workshop title and description source drafts live in `.github/workshop/descriptions/english.txt` and `.github/workshop/descriptions/koreana.txt`. Do not put raw external URLs in Workshop descriptions; use Steam-native Required Items, guides, or discussions for links to avoid Steam automated content review holds.

## Verification

- There is no normal automated Lua test suite for this mod.
- For Python generator changes, run `python3 -m py_compile generate_xml.py`.
- After changing generated-content rules, run `python3 generate_xml.py` in a Python environment with Pillow and inspect `content/gfx/death_items.png`.
- For Lua syntax checks, use the local Lua tooling only if available in the environment.
- For gameplay changes, verify in-game with debug mode off and then with debug mode on only when logs are needed.

## External Isaac Docs

- Use `ISAAC_DOCS_REFERENCE.md` for a quick map of which Wofsauge Isaac Docs pages to open for callbacks, entities, item XML, item pools, save data, rendering, and common enums.
- Prefer `https://wofsauge.github.io/IsaacDocs/rep/` pages. Treat `/abp/` and `oldDocs` search results as legacy references unless a task explicitly targets older API behavior.
