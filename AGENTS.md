# AGENTS.md

## Maintaining AGENTS.md

- Read the nearest applicable `AGENTS.md` before repository work and treat it as active project memory, not a static reference.
- When a user establishes a durable convention, architectural invariant, recurring workflow, wording rule, or verification requirement, update the appropriate `AGENTS.md` section during the same task. Do not record one-off feature requests, temporary debugging details, secrets, or volatile implementation values.
- Before final verification, re-read the affected `AGENTS.md` sections so code, metadata, descriptions, and validation remain consistent with the recorded rules.

## Project Overview

This repository is a The Binding of Isaac mod named "Conch's Blessing". The Steam install directory is named "Rebirth", but that directory name does not establish the supported executable/API baseline. The repository currently does not pin a minimum Repentance or Repentance+ build, so preserve existing capability checks and fallbacks unless the support policy is explicitly changed.

Runtime load order is:

1. `main.lua` requires `scripts/conch_blessing_core.lua`.
2. Core hard-gates initialization on StatsAPI, creates the IsaacScript Common-upgraded `ConchBlessing` mod, initializes SaveManager/config/MCM/HiddenItemManager, and attaches the external StatsAPI tables.
3. Core requires `scripts/conch_blessing_items.lua`; the item loader then requires `scripts/eid_language.lua`, `scripts/callback_manager.lua`, and the item behavior modules.
4. Core finally loads `scripts/conch_blessing_upgrade.lua` and `scripts/conch_blessing_highlight.lua`.

Item behavior usually lives under `scripts/items/collectibles`, `scripts/items/trinkets`, or `scripts/items/familiars`. The repository does not yet have a generic monster, room, or stage registry/loader. Do not assume those content types are handled by `ConchBlessing.ItemData`.

The mod depends on external runtime APIs:

- StatsAPI is a hard runtime dependency; without `_G.StatsAPI.stats.unifiedMultipliers`, core initialization stops.
- Magic Conch supplies the upgrade callback API used by `scripts/conch_blessing_upgrade.lua` and is a required Workshop dependency.
- Mod Config Menu and EID integrations are optional at runtime and must remain guarded when their globals or methods are unavailable.
- EID descriptions and icons are generated from item data in `scripts/conch_blessing_items.lua` and `scripts/eid_language.lua`.
- REPENTOGON is recommended, not a blanket hard dependency; individual features may require it or provide a vanilla fallback as documented below.

Core subsystem map:

- `scripts/callback_manager.lua` owns callback-key to `ModCallbacks` registration.
- `scripts/template.lua` owns upgrade morph visuals before/after item conversion.
- `scripts/conch_blessing_config.lua` owns language/debug/spawn settings.
- `scripts/conch_blessing_mcm.lua` owns MCM UI and setting persistence.
- `scripts/lib/weapon_attack_tracker.lua` owns reusable direct-player weapon-trigger counting and direction resolution; item modules own and reset their own counter state.
- `scripts/lib/damage_provenance.lua` owns actual attack-source resolution, direct-player tear eligibility, and namespaced secondary-attack marking/inheritance for damage-triggered procs.
- External `StatsAPI.stats` owns unified stat multipliers and the multiplier display; there is no local `scripts/lib/stats.lua`.
- `ConchBlessing` is the IsaacScript Common-upgraded mod object. `ConchBlessing.originalMod` is the raw `RegisterMod` reference retained for support-library and legacy call sites.

## API And Content Sources Of Truth

- Keep project invariants, ownership, and recurring workflows in this file. Keep API signatures, enum/XML field lists, and tool links in `ISAAC_DOCS_REFERENCE.md`; do not turn `AGENTS.md` into a copy of external API documentation.
- For an exact API call, check sources in this order: the intended game-build documentation, the exact class or callback page, related enum/XML pages, the provider's documentation/source for external APIs, and then runtime behavior.
- `https://wofsauge.github.io/IsaacDocs/rep/` currently documents the Repentance+ base API. A method appearing there does not prove that it exists on every older Repentance build this mod might still support.
- Until the repository pins a minimum game build, preserve existing guards. For a new disputed or newer-only API, either select and test an explicit target baseline in the same change or use a capability-checked fallback; if the feature cannot degrade safely, stop and make the dependency/support-policy decision explicit before implementation.
- Use `https://repentogon.com/docs.html` for REPENTOGON additions. Editor autocomplete and `.luarc.json` globals are development aids, not proof that an API exists in the target runtime.
- When available, use the game installation's `../../extracted_resources/resources` as a read-only vanilla XML/ANM2/room reference and `../../tools` for the Resource Extractor and animation tools. Re-extract after game updates before relying on vanilla implementation details.
- For StatsAPI, Magic Conch, MCM, EID, StageAPI, or another mod API, inspect the installed/declared provider version and guard optional capabilities. Never infer a third-party contract only from this mod's call site.
- If documentation, extracted resources, and runtime disagree, preserve compatibility with capability checks and test the intended baseline in game. Record project-wide compatibility conclusions here or in `ISAAC_DOCS_REFERENCE.md`; keep a narrow API quirk beside the affected code.

## Files To Treat Carefully

- `scripts/lib/isaacscript-common.lua` is vendored and very large. Do not edit it unless the task explicitly requires a vendor patch.
- `scripts/lib/save_manager.lua` and `scripts/lib/hidden_item_manager.lua` are shared support libraries. Prefer changing call sites first.
- `content/items.xml`, `content/itempools.xml`, `content/entities2.xml`, `content/gfx/death_items.anm2`, and `content/gfx/death_items.png` are generator-owned outputs. Do not hand-edit them unless the generation workflow is intentionally being changed.
- `generate_xml.py` currently rebuilds all of `content/entities2.xml` from familiar entries in `ConchBlessing.ItemData`, forces entity type `3`, and does not preserve manual non-familiar entries. Before adding a monster, NPC, custom effect, or other non-familiar entity, first extend the source schema/generator or replace it with a documented merge/manual source-of-truth workflow.
- `metadata.xml` is hand-authored release metadata. Do not conflate it with generated content or change its version unless the version rules below authorize it.
- Text files are UTF-8. On Windows, explicitly read and write UTF-8 when a tool's default encoding is ambiguous; apparent mojibake can be a terminal decoding issue. Avoid broad encoding normalization or translation rewrites outside a text/encoding task.
- Treat files under `../../extracted_resources` and other installed mods as read-only references. Never copy another mod's implementation or assets into this repository.

## Code Style

- Keep Lua changes small and local to the item or subsystem being modified.
- Treat user examples as acceptance cases, not implementation conditions. Implement the underlying gameplay event or state transition once so it applies consistently to current and future content; do not enumerate known items, protections, entities, or room cases to simulate the requested result.
- Prefer the engine's canonical semantic operation (for example real death, acquisition, spawn, or room transition) over manipulating adjacent side effects until the example appears to work. If no canonical API exists, introduce one centralized, capability-checked abstraction with a documented fallback and limitation instead of scattered special-case branches.
- Prefer existing patterns: add item definitions to `ConchBlessing.ItemData`, then register behavior through the `callbacks` table.
- Keep `ConchBlessing.ItemData` grouped in this order: collectible items (`passive` and `active`) first, familiar items second, trinkets last. Append new items to the end of their group because generated `content/items.xml` IDs follow this registry order.
- Generated XML follows the registry's textual order, but runtime item scripts are loaded with `pairs`; do not make runtime initialization depend on ItemData iteration order.
- Keep one global table per item namespace, for example `ConchBlessing.dragon` or `ConchBlessing.chronus`.
- Use `local` helpers and constants inside item files. Do not add globals unless they are part of the existing `ConchBlessing.*` API.
- Use `ConchBlessing.printDebug` for optional logs and `ConchBlessing.printError` for real failures. Avoid unconditional `Isaac.ConsoleOutput` in normal paths.

## Non-Item Content Expansion

- There is currently no `scripts/entities`, `scripts/rooms`, `scripts/stages`, `content/rooms`, or StageAPI integration in this repository. These are unimplemented extension areas, not implicit parts of the item registry.
- When the first non-item subsystem is introduced, give it an explicit registry/loader required by `scripts/conch_blessing_core.lua` after shared managers are ready. Record its exact load order and metadata source here in the same change. Do not hide monsters, rooms, or stages inside `ConchBlessing.ItemData` merely to reuse the item callback manager.
- Prefer future behavior paths such as `scripts/entities/<category>/<key>.lua`, `scripts/rooms/<key>.lua`, and `scripts/stages/<key>.lua`. Create only the paths needed by the implemented subsystem and keep one clear Lua namespace/registry entry per content key.
- Namespace new non-item runtime assets under a mod-specific path such as `resources/gfx/conch_blessing/...` to reduce cross-mod resource collisions. Existing assets do not need to be moved solely for consistency.

### Custom Entities And Monsters

- Define each custom entity's XML metadata and Lua identity from one documented source of truth. Keep the name and type/variant/subtype consistent across `entities2.xml`, Lua, and room layouts; avoid scattering unexplained numeric IDs. Prefix new XML names and runtime data keys with a Conch Blessing-specific namespace to avoid cross-mod collisions.
- Resolve custom entity IDs with `Isaac.GetEntityTypeByName` and `Isaac.GetEntityVariantByName` after XML is loaded, cache the results, and call `ConchBlessing.printError` and skip registration if lookup returns an invalid value.
- `content/entities2.xml` declares entity identity, physics, health/tags, and its `anm2path`; the ANM2 and spritesheets are runtime assets under `resources/gfx`. With the current root `anm2root="gfx/"`, entity `anm2path` values are relative to `resources/gfx`, and ANM2 spritesheet paths are relative to the ANM2/runtime resource rules.
- Register NPC callbacks when the entity subsystem loads, not through the delayed ItemData callback pass. Use the callback's supported type parameter, then return early on variant and subtype before doing AI, room scans, target selection, or rendering work.
- Model AI as explicit semantic states. Prefer `Sprite:IsEventTriggered`, `Sprite:IsFinished`, pathfinding/target state, and collision events over hardcoded animation frame numbers or global frame counts.
- Keep transient entity state in `Entity:GetData()` under a sufficiently unique key such as `__ConchBlessing...`, or in a room-scoped runtime table. `GetData()` is shared by every mod. Persist only serializable state that must survive a transition through SaveManager, and clear cached entity references on removal, room change, new level, game exit, and mod unload as applicable.
- Use seeded entity/room RNG for attacks, drops, and room-authored random choices. Prefer `Game():Spawn` with a deterministic nonzero seed when spawn identity matters. Test friendly/charmed/frozen states and multiplayer targeting when the entity can interact with them.
- Treat kill, completed NPC death, entity removal, and room-unload cleanup as different lifecycle events. `MC_POST_ENTITY_REMOVE` alone is not proof that an entity died.

### Rooms, Room Packs, And Stages

- Distinguish runtime room behavior (`Room`, `Level`, `RoomDescriptor`, callbacks) from authored room layouts (`.stb`). Create Repentance-compatible layouts with Basement Renovator or another verified compatible editor; do not hand-edit binary STB files.
- Vanilla-pool room packs belong under `content/rooms` and must use the stage filenames/formats expected by the game/editor. Verify stage, room type, shape, doors, difficulty/weight, and custom entity IDs against extracted vanilla rooms before committing. `resources/rooms` replaces vanilla room sets and is not the default additive path.
- Use `MC_PRE_ROOM_ENTITY_SPAWN` only for layout-spawn substitution, `MC_POST_NEW_ROOM` for room-entry state, and `MC_PRE_SPAWN_CLEAN_AWARD` for pre-award behavior. Read their return contracts before implementation; the local CallbackManager alias `postRoomClear` still maps to the pre-award callback.
- Key room state through `SaveManager.GetRoomSave(..., listIndex)` using the relevant `RoomDescriptor.ListIndex`; do not persist descriptor userdata or rely only on `Level:GetCurrentRoomIndex()`. Choose normal versus `noHourglass` storage deliberately, and account for first visit, room shape, dimension, revisit, continue, Glowing Hourglass, Curse of the Maze, and special rooms outside the normal map when relevant.
- The base `MC_LEVEL_GENERATOR` callback is documented as inactive/broken and must not be used to build floors. Full custom floors or dynamic placement require an explicit architecture choice such as REPENTOGON room/level-generation APIs or StageAPI; neither is currently a project dependency.
- Do not add StageAPI, make REPENTOGON mandatory for the whole mod, or replace vanilla stage resources without an explicit compatibility/dependency decision. `resources/stages.xml` replaces vanilla data and `content/stages.xml` has no effect, so stages require a dedicated compatibility plan.
- Do not conflate entity type/variant/subtype, room type/variant/subtype, `LevelStage`, `StageType`, STB stage IDs, or entity `bossID`; they are different identifier domains even when numeric values overlap.
- Vanilla grid entities can be spawned or changed, but a brand-new grid-entity type requires an explicitly adopted extender/framework mechanism or a normal entity/effect emulation.
- Custom bosses require more than an NPC flag: room layouts, boss-pool/framework integration, portraits/transition assets, doors/clear behavior, and bestiary behavior must be designed and verified together. Route exact fields and APIs through `ISAAC_DOCS_REFERENCE.md`.

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
- For item behavior, prefer `ItemData.callbacks` plus `CallbackManager` over scattered direct `AddCallback` calls.
- `scripts/callback_manager.lua` is an ItemData registrar, not a generic entity/room callback framework: it iterates only `ConchBlessing.ItemData`, delays registration until `MC_POST_GAME_STARTED`, and only auto-filters familiar variants. Do not route a new entity or room subsystem through it without redesigning and verifying those semantics.
- CallbackManager keys are conveniences, not API contracts. Confirm the mapped `ModCallbacks` value, supported filter parameter, callback phase, arguments, and return behavior in both `callback_manager.lua` and the current docs before implementing a callback.
- Match documented callback argument order exactly. Never hide a shifted or missing player argument by falling back to `Isaac.GetPlayer(0)`; reject invalid callback input and preserve the actual triggering player in multiplayer.
- Do not register empty callbacks through `ItemData.callbacks`.
- Cache static `ItemConfig` scans and repeated ID lists. Do not scan `CollectibleType.NUM_COLLECTIBLES` every frame.
- Avoid repeated `Isaac.GetRoomEntities()` or `Isaac.FindByType()` in per-entity update callbacks. Cache per-frame data or store runtime references when safe.
- Preserve multiplayer behavior by iterating `Game():GetNumPlayers()` when the effect can belong to any player.
- For attack-count thresholds, never group projectile callbacks by game frame. Reuse `scripts/lib/weapon_attack_tracker.lua` with the engine's semantic attack event. Breath and Dragon use REPENTOGON `MC_POST_TRIGGER_WEAPON_FIRED`: advance once per callback, never by `FireAmount` or `Weapon:GetNumFired`, and attribute only a direct `EntityPlayer` weapon owner. Multishot and familiar-owned mirror weapons must not add counts, while item-spawned secondary entities must not re-enter the counter. The base API has no exact fallback, and familiar-only weapon attacks have no shared player-action token; keep those dependency and scope limits explicit rather than restoring frame inference or item/familiar special cases.
- Prefer semantic callbacks and explicit state transitions over frame numbers or fixed frame delays. Do not infer game initialization, pickup completion, room readiness, or session phase from `Game():GetFrameCount()` when an ownership, pickup, room, entity, or queue event can establish it directly.
- If a frame delay is unavoidable because the engine exposes no readiness event, document the reason, bound the wait, and clear pending state when a game or room transition invalidates that work.

## Damage Triggers And Provenance

- A collision callback proves contact, not applied HP damage. Base `MC_ENTITY_TAKE_DMG` runs before damage and may still be cancelled or changed; when a proc contract requires damage that actually occurred, use REPENTOGON `MC_POST_ENTITY_TAKE_DMG` or make the weaker fallback and its limitation explicit.
- Classify damage by its actual attack entity, not by an adjacent effect or a negative list of known attacks. For REPENTOGON post-damage callbacks, inspect `ExtraSource.Entity` first and fall back to `Source.Entity`; `ExtraSource` preserves laser, knife, and other hitbox provenance that the normal source may collapse to a player.
- Existing engine `DamageFlag` values may be bitwise-ORed and passed when code directly invokes a damage API such as `Entity:TakeDamage`, `Game:BombDamage`, or `Game:BombExplosionEffects`. Native spawned attacks normally receive their damage flags from the engine; do not assume an entity's `Flags` field contains `DamageFlag` values (`EntityBomb.Flags`, for example, contains `TearFlags`).
- There is no `DAMAGE_TEAR` and no safe project-owned `DamageFlag` or `TearFlags` bit allocation. Positively identify direct tear damage with `sourceEntity:ToTear()`. Mark mod-created secondary attacks with a namespaced `Entity:GetData()` provenance record such as `__ConchBlessingDamageProvenance`, propagate it at semantic child-spawn/split events, and fail closed when required provenance cannot be established.
- Reuse `scripts/lib/damage_provenance.lua` for shared classification. SOFLAM missiles and Void Dagger rings are marked as proc-ineligible secondary attacks, and their spawned tear/bomb/laser children inherit that record. Add future secondary attacks at their semantic spawn point instead of adding item-name exclusions to each consumer.
- When both an applied-damage callback and a base collision fallback are registered, the fallback must return before dedupe, lockout, RNG, or other state changes whenever `MC_POST_ENTITY_TAKE_DMG` is available. The fallback must also reject proc-ineligible provenance; its collision-only limitation remains part of the REPENTOGON-recommended compatibility path.
- Do not create a generic damage-flag setter merely to wrap bitwise OR. Do not extend `scripts/lib/damage_utils.lua` as a provenance registry because it is a legacy self-damage classifier and `ConchBlessing.DamageUtils` may be replaced by StatsAPI's implementation. Do not use `DAMAGE_CLONES` as a generic origin marker; reserve it for preventing recursive damage re-entry when code deliberately calls `TakeDamage` again.

## Choice Rooms And Pickup State

- When disabling vanilla option linkage or return behavior in a choice room, preserve the one-choice invariant explicitly: scope pending state to the room or session, finalize only after confirmed acquisition, remove only the intended pickup class, and reset that state when a transition invalidates its scope.
- Bind pending pickup and choice state to the selecting player's stable identity and block concurrent second selections while the first selection is unresolved. Do not assume `Isaac.GetPlayer(0)` in multiplayer-sensitive flows.
- Shared special dimensions must distinguish the active session or mode and clear that state on any exit from the dimension, not only on the expected return-room transition.

## Player Death And Revival

- For this project's unavoidable-but-revivable death effects, use the engine's direct `Entity:Kill()` path instead of lethal `TakeDamage`; do not simulate the outcome by consuming shields/lives, removing the player entity, or suppressing revival handling.
- Treat the API choice as complete only after in-game matrix verification: damage-prevention states must not prevent the death, while the intended vanilla and declared-mod revival effects must still revive the player. If runtime behavior contradicts that contract, fix the semantic death path rather than adding protection-specific branches.

## Stats, Config, And Debug

- Use `ConchBlessing.stats.unifiedMultipliers` for stat changes. Avoid raw stat overwrites unless the existing item pattern requires it.
- Respect tears SPS/MaxFireDelay conversion when changing fire-rate behavior.
- Minimize cache invalidations. Call `AddCacheFlags` and `EvaluateItems` only when state changes require recalculation.
- Use player/item-based RNG such as `InitSeed` or collectible RNG where deterministic behavior matters.
- Resolve language through `ConchBlessing_Config.GetCurrentLanguage`; MCM language changes should re-register EID descriptions when needed.
- Debug output should go through `ConchBlessing.printDebug`, `ConchBlessing.print`, or `ConchBlessing.printError`, include relevant player/item/cache context, and avoid hardcoded magic values.
- Upgrade visuals should use `Template.*.onBeforeChange` and `Template.*.onAfterChange` patterns; cosmetic effects should remain harmless.

## REPENTOGON Dependency And EID

- REPENTOGON is a script extender with its own versioned API. Do not maintain a broad remembered list of REPENTOGON-only methods here: current Repentance+ has absorbed some APIs that older builds lacked, while editor stubs can expose extender methods as if they were universal. Check the current base page and the matching `repentogon.com` page for every disputed method.
- The collectible-pedestal cycle methods used by this repository (`EntityPickup:GetCollectibleCycle`, `AddCollectibleCycle`, `RemoveCollectibleCycle`, and `TryInitOptionCycle`) and `Level:GetDimension` remain known extender boundaries for existing code. Other APIs must be classified at task time against the intended minimum game build.
- Guard every API not guaranteed by the declared minimum runtime with a `type(obj.Method) == "function"` check or `pcall`, and provide a fallback whenever technically possible. Do not remove a guard merely because the current local Repentance+ or REPENTOGON installation provides the method.
- Treat an effect as REPENTOGON-required only when no supported-base implementation exists. If a new non-item subsystem makes REPENTOGON a whole-mod requirement, update `metadata.xml`, README/Workshop dependency text, and load-time handling; item EID warnings alone are not sufficient.
- Any item that calls a REPENTOGON-only API must note it in the item's `eid` block with a short fixed phrase only. Do not add reasons, API names, or fallback details in the EID.
  - No vanilla fallback: keep the required warning `#{{Warning}} REPENTOGON이 필요합니다!` (en `#{{Warning}} Requires REPENTOGON!`). Example: `severed_oath`.
  - Has a vanilla fallback: use `#{{Warning}} REPENTOGON 권장` (en `#{{Warning}} REPENTOGON recommended`), nothing more. Examples: `appraisal_certificate`, `soflam`, `void_dagger`.
- When adding or changing an item's REPENTOGON usage, update its EID note so the required-vs-fallback wording stays accurate. Items with no REPENTOGON call need no note.
- When player-visible behavior changes, update any affected EID or synergy entries in both Korean and English. Describe important cleanup and suppressed vanilla behavior, and keep multi-line Korean and English entries structurally parallel.

## Save Data

- Use `ConchBlessing.SaveManager` for persistent and run-scoped state.
- When a system grants ordinary collectible copies that must later be removed while identical player-owned copies may coexist, inventory totals are not ownership. Persist the active system-owned contribution and the player's pre-grant baseline, update them together, and remove only copies above that baseline. If a cap means “ever during this ownership” rather than “currently active,” persist that lifetime total separately. Chronus familiar conversions use `itemGrants`, `itemGrantBaselines`, and `itemGrantTotals` for these roles.
- Choose the narrowest matching scope: `GetRunSave`, `GetFloorSave`, `GetRoomSave`, or `GetTempSave`. Pass the actual player/entity when state has an owner, and use `noHourglass` only when reversal is intentionally suppressed.
- Use `GetPersistentSave` for non-setting data that must survive across runs, such as project-managed unlock state, and `GetSettingsSave` for configuration. These file scopes do not have matching `TryGet*` forms; consult the vendored annotations instead of inferring one.
- In multiplayer, bind state to the callback's triggering player or SaveManager's entity-scoped save. Do not use player 0 or a module-global table as a substitute for ownership unless the design is explicitly shared across all players.
- Store persistent MCM/settings data under `SaveManager.GetSettingsSave().config` through the existing config helpers.
- Store serializable data only. Do not write entity, sprite, font, RNG, or userdata objects into saved tables.
- If runtime entity references are cached, clear them on room/game transitions and keep them out of SaveManager data.

## Generated Content

- After creating an item or changing generator-consumed item/familiar metadata in `scripts/conch_blessing_items.lua`, run `python3 generate_xml.py` from the repository root in a Python environment with Pillow to update `content/items.xml`, `content/itempools.xml`, `content/entities2.xml`, `content/gfx/death_items.anm2`, and `content/gfx/death_items.png`. EID-only wording does not affect these outputs. If using uv, use `uv run python generate_xml.py`; this repository does not define a `generate_xml` console command.
- The current generator understands item metadata and familiar entity metadata only. It is not a general `entities2.xml`, room, monster, boss, sound, or stage generator. Extend its input schema and verification before assigning ownership of a new content type to it.
- Because the generator rewrites `content/entities2.xml`, never add a manual custom-entity entry and then run the generator. A custom-entity change is incomplete until its source survives a second generator run with no semantic diff.
- After changing collectible or familiar item sprites under `resources/gfx/items/collectibles`, run `python3 generate_xml.py` in a Python environment with Pillow so generated death item spritesheets stay in sync.
- `content/gfx/death_items.png` generation requires Pillow. By default it preserves resized source icon colors. Use `--death-palette vanilla` to generate the vanilla death-screen color style (`RGB(54, 47, 45)` with alpha levels).
- Death item resizing defaults to trimming transparent source padding and fitting into the 16x16 death frame. Use `--death-resize raw_resize` for the original behavior: resize the full source image directly to 16x16 without trimming.
- Local git hooks live in `.githooks`; enable them with `git config core.hooksPath .githooks`. The `pre-push` hook runs `python3 generate_xml.py`; it amends only generated content files into `HEAD` when they changed, then stops that push so the same push command can be run again with the amended commit. The local `python3` environment must have Pillow installed.
- Workshop packaging recursively includes `content/`, `resources/`, and `scripts/`, plus the allowed root runtime files in `.github/scripts/prepare_steam_workshop_upload.py`. New runtime files inside those trees need no manifest change; a new root-level runtime file requires an explicit packaging update.

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
- For any generated XML change, parse or validate the XML, run the generator twice, and confirm the second run produces no diff. If entity generation changes, confirm both existing familiars and every new non-familiar entry survive.
- For Lua syntax checks, use the local Lua tooling only if available in the environment.
- For gameplay changes, verify in-game with debug mode off and then with debug mode on only when logs are needed.
- After XML, ANM2, STB, sound, or spritesheet changes, fully restart the game and inspect the game log for parse and missing-resource errors; a Lua-only reload is not sufficient verification.
- For a custom entity or monster, verify name-to-ID lookup and console spawning, every animation/event and AI state, collision/damage/death/removal, room exit/re-entry, continue behavior, and any friendly/charmed/frozen or multiplayer paths the design supports.
- For a custom effect, verify animation completion, timeout/removal, pause behavior, and every room/game transition that can invalidate it; confirm no orphan entity or permanently active broad callback remains.
- For an authored room, verify it in the room editor and through natural seeded generation in game. Check every supported shape/door, grid and entity placement, room clear and award behavior, revisit/continue, and that custom entity IDs match the runtime XML.
- For room placement or stage work, test normal and alternate stages, applicable dimensions, Curse of the Maze/Glowing Hourglass transitions, Greed Mode if supported, and compatibility without optional frameworks. If a framework becomes required, verify the missing-dependency failure path too.

## External Isaac Docs

- Use `ISAAC_DOCS_REFERENCE.md` as the maintained routing map for callbacks, entities, room authoring/runtime data, XML, animation, item pools, save data, rendering, REPENTOGON, and common enums.
- Prefer `https://wofsauge.github.io/IsaacDocs/rep/` for the current Repentance+ base API and `https://repentogon.com/docs.html` for extender APIs. Treat `/abp/` and `oldDocs` search results as legacy references unless a task explicitly targets older behavior.
- When the project needs compatibility with pre-Repentance+ builds, use the installed build's `tools/LuaDocs`, extracted resources, provider source, and runtime checks; the current `/rep/` site alone is not a compatibility guarantee.
