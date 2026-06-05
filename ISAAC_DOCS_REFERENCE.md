# Isaac Docs Reference Map

Last checked: 2026-05-19

Primary docs: https://wofsauge.github.io/IsaacDocs/rep/

This file is a routing guide for Wofsauge's Binding of Isaac Lua API docs. Use it to decide which docs page to open before changing this mod.

## Basic Rules

- Use the `/rep/` docs first. Search engines often return `/abp/` or `oldDocs`; those are legacy references unless the task is explicitly about old API behavior.
- For behavior questions, read in this order: class/function page, related enum page, related XML page, then tutorial or FAQ page.
- For callbacks, always read the callback signature, optional parameter matching, and return-value behavior before returning anything from a callback.
- For item content, remember the local source of truth: item metadata starts in `scripts/conch_blessing_items.lua`, then `generate_xml.py` may regenerate `content/items.xml` and `content/itempools.xml`.
- The docs are community-maintained. If a documented behavior differs from in-game behavior, trust runtime testing and leave a short note near the affected code only when it prevents future mistakes.

## Quick Lookup

| If you need to know... | Open first | Also check |
| --- | --- | --- |
| Which callback fires, its arguments, and what return values mean | [ModCallbacks](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html) | [Isaac:AddCallback / AddPriorityCallback](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html), [CallbackPriority](https://wofsauge.github.io/IsaacDocs/rep/enums/CallbackPriority.html) |
| How to register callbacks, spawn entities, find players, use mod data, or render text | [Isaac](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html) | [Game](https://wofsauge.github.io/IsaacDocs/rep/Game.html), [Mod Reference](https://wofsauge.github.io/IsaacDocs/rep/ModReference.html) |
| Player inventory, active item charge, trinkets, cards, pills, costumes, stats, and cache evaluation | [EntityPlayer](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html) | [CacheFlag](https://wofsauge.github.io/IsaacDocs/rep/enums/CacheFlag.html), [TemporaryEffects](https://wofsauge.github.io/IsaacDocs/rep/TemporaryEffects.html), [ActiveSlot](https://wofsauge.github.io/IsaacDocs/rep/enums/ActiveSlot.html) |
| Passive stat items | [MC_EVALUATE_CACHE](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html#mc_evaluate_cache) | [EntityPlayer stat fields](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html), [items.xml cache attribute](https://wofsauge.github.io/IsaacDocs/rep/xml/items.html) |
| Active item use behavior | [MC_USE_ITEM](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html#mc_use_item) and [MC_PRE_USE_ITEM](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html#mc_pre_use_item) | [UseFlag](https://wofsauge.github.io/IsaacDocs/rep/enums/UseFlag.html), [items.xml maxcharges/chargetype](https://wofsauge.github.io/IsaacDocs/rep/xml/items.html), [EntityPlayer:UseActiveItem](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html) |
| Item IDs, quality, tags, charge type, cache flags, item config fields | [items.xml](https://wofsauge.github.io/IsaacDocs/rep/xml/items.html) | [ItemConfig functions](https://wofsauge.github.io/IsaacDocs/rep/ItemConfig.html), [ItemConfig item fields](https://wofsauge.github.io/IsaacDocs/rep/ItemConfig_Item.html), [ItemConfig enum](https://wofsauge.github.io/IsaacDocs/rep/enums/ItemConfig.html) |
| Item pools, pool names, item weight, and pool runtime behavior | [itempools.xml](https://wofsauge.github.io/IsaacDocs/rep/xml/itempools.html) | [ItemPool](https://wofsauge.github.io/IsaacDocs/rep/ItemPool.html), [ItemPoolType](https://wofsauge.github.io/IsaacDocs/rep/enums/ItemPoolType.html), [Itempool Editor](https://wofsauge.github.io/IsaacDocs/rep/tutorials/Tool_ItemPoolEditor.html) |
| Pickups, collectible pedestals, prices, morphing, and shop state | [EntityPickup](https://wofsauge.github.io/IsaacDocs/rep/EntityPickup.html) | [PickupVariant](https://wofsauge.github.io/IsaacDocs/rep/enums/PickupVariant.html), [PickupPrice](https://wofsauge.github.io/IsaacDocs/rep/enums/PickupPrice.html), [Room:FindFreePickupSpawnPosition](https://wofsauge.github.io/IsaacDocs/rep/Room.html) |
| Entity basics shared by enemies, pickups, tears, effects, familiars, and players | [Entity](https://wofsauge.github.io/IsaacDocs/rep/Entity.html) | [EntityType](https://wofsauge.github.io/IsaacDocs/rep/enums/EntityType.html), [EntityFlag](https://wofsauge.github.io/IsaacDocs/rep/enums/EntityFlag.html), [EntityRef](https://wofsauge.github.io/IsaacDocs/rep/EntityRef.html) |
| NPC/enemy behavior, targeting, states, damage, collisions, and death | [EntityNPC](https://wofsauge.github.io/IsaacDocs/rep/EntityNPC.html) | [NpcState](https://wofsauge.github.io/IsaacDocs/rep/enums/NpcState.html), [DamageFlag](https://wofsauge.github.io/IsaacDocs/rep/enums/DamageFlag.html), [MC_ENTITY_TAKE_DMG](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html#mc_entity_take_dmg) |
| Effects, animations, particles, overlays, and non-pickup visual entities | [EntityEffect](https://wofsauge.github.io/IsaacDocs/rep/EntityEffect.html) | [EffectVariant](https://wofsauge.github.io/IsaacDocs/rep/enums/EffectVariant.html), [Sprite](https://wofsauge.github.io/IsaacDocs/rep/Sprite.html), [SFXManager](https://wofsauge.github.io/IsaacDocs/rep/SFXManager.html) |
| Tears, tear flags, projectiles, lasers, knives, or weapon-like entities | [EntityTear](https://wofsauge.github.io/IsaacDocs/rep/EntityTear.html) | [TearFlags](https://wofsauge.github.io/IsaacDocs/rep/enums/TearFlags.html), [EntityProjectile](https://wofsauge.github.io/IsaacDocs/rep/EntityProjectile.html), [ProjectileFlags](https://wofsauge.github.io/IsaacDocs/rep/enums/ProjectileFlags.html), [EntityLaser](https://wofsauge.github.io/IsaacDocs/rep/EntityLaser.html), [EntityKnife](https://wofsauge.github.io/IsaacDocs/rep/EntityKnife.html) |
| Familiars, follower/orbit behavior, and custom familiar counts | [EntityFamiliar](https://wofsauge.github.io/IsaacDocs/rep/EntityFamiliar.html) | [EntityPlayer:CheckFamiliar](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html), [FamiliarVariant](https://wofsauge.github.io/IsaacDocs/rep/enums/FamiliarVariant.html), [MC_FAMILIAR_INIT / MC_FAMILIAR_UPDATE](https://wofsauge.github.io/IsaacDocs/rep/enums/ModCallbacks.html) |
| Room state, doors, grid entities, positions, enemy counts, first visit, clear state | [Room](https://wofsauge.github.io/IsaacDocs/rep/Room.html) | [GridEntity](https://wofsauge.github.io/IsaacDocs/rep/GridEntity.html), [DoorSlot](https://wofsauge.github.io/IsaacDocs/rep/enums/DoorSlot.html), [RoomType](https://wofsauge.github.io/IsaacDocs/rep/enums/RoomType.html), [RoomShape](https://wofsauge.github.io/IsaacDocs/rep/enums/RoomShape.html) |
| Floor/stage data, curses, map rooms, room descriptors, new level flow | [Level](https://wofsauge.github.io/IsaacDocs/rep/Level.html) | [RoomDescriptor](https://wofsauge.github.io/IsaacDocs/rep/RoomDescriptor.html), [LevelStage](https://wofsauge.github.io/IsaacDocs/rep/enums/LevelStage.html), [StageType](https://wofsauge.github.io/IsaacDocs/rep/enums/StageType.html), [LevelCurse](https://wofsauge.github.io/IsaacDocs/rep/enums/LevelCurse.html) |
| Whole-run state, players, item pool access, room transitions, global game frame count | [Game](https://wofsauge.github.io/IsaacDocs/rep/Game.html) | [GameStateFlag](https://wofsauge.github.io/IsaacDocs/rep/enums/GameStateFlag.html), [Seeds](https://wofsauge.github.io/IsaacDocs/rep/Seeds.html), [ItemPool](https://wofsauge.github.io/IsaacDocs/rep/ItemPool.html) |
| RNG usage and seeded randomness | [RNG](https://wofsauge.github.io/IsaacDocs/rep/RNG.html) | `Entity:GetDropRNG()`, `EntityPlayer:GetCollectibleRNG()`, `Room:GetSpawnSeed()`, `Game():GetSeeds()` |
| Saving, loading, and where save files live | [Storing Data](https://wofsauge.github.io/IsaacDocs/rep/tutorials/storing-data.html) | [Directories and save files](https://wofsauge.github.io/IsaacDocs/rep/tutorials/directories-and-save-files.html), [Isaac.SaveModData / LoadModData](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html) |
| Mod folder layout and multi-file Lua loading | [Mod Organization](https://wofsauge.github.io/IsaacDocs/rep/tutorials/mod-organization.html) | [Using additional .lua Files](https://wofsauge.github.io/IsaacDocs/rep/tutorials/Using-Additional-Lua-Files.html), this repo's `main.lua` load order |
| Custom callbacks provided by other mods or libraries | [Custom Callbacks tutorial](https://wofsauge.github.io/IsaacDocs/rep/tutorials/CustomCallbacks.html) | The provider mod's docs and source |
| Costumes, costume XML, player appearance, and `.anm2` layer order | [costumes2.xml](https://wofsauge.github.io/IsaacDocs/rep/xml/costumes2.html) | [Adding Costumes without LUA](https://wofsauge.github.io/IsaacDocs/rep/tutorials/AddingCostumesWithoutLUA.html), [Sprite](https://wofsauge.github.io/IsaacDocs/rep/Sprite.html), [EntityPlayer costume methods](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html) |
| Custom entities declared through XML | [entities2.xml](https://wofsauge.github.io/IsaacDocs/rep/xml/entities2.html) | [Entities overview](https://wofsauge.github.io/IsaacDocs/rep/entities/Overview.html), [Isaac.GetEntityTypeByName / GetEntityVariantByName](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html) |
| Input hooks or reading player/controller input | [Input](https://wofsauge.github.io/IsaacDocs/rep/Input.html) | [ButtonAction](https://wofsauge.github.io/IsaacDocs/rep/enums/ButtonAction.html), [InputHook](https://wofsauge.github.io/IsaacDocs/rep/enums/InputHook.html), [EntityPlayer input methods](https://wofsauge.github.io/IsaacDocs/rep/EntityPlayer.html) |
| HUD, render callbacks, screen/world coordinates, and text rendering | [HUD](https://wofsauge.github.io/IsaacDocs/rep/HUD.html) | [Font](https://wofsauge.github.io/IsaacDocs/rep/Font.html), [Render text tutorial](https://wofsauge.github.io/IsaacDocs/rep/tutorials/Tutorial-Rendertext.html), [Isaac screen/world conversion methods](https://wofsauge.github.io/IsaacDocs/rep/Isaac.html) |
| Sound and music IDs or playback | [SFXManager](https://wofsauge.github.io/IsaacDocs/rep/SFXManager.html) | [SoundEffect](https://wofsauge.github.io/IsaacDocs/rep/enums/SoundEffect.html), [MusicManager](https://wofsauge.github.io/IsaacDocs/rep/MusicManager.html), [Music enum](https://wofsauge.github.io/IsaacDocs/rep/enums/Music.html) |
| XML validation or editing external content files | [XML Validator](https://wofsauge.github.io/IsaacDocs/rep/tutorials/Tool_XMLValidator.html) | [Tools overview](https://wofsauge.github.io/IsaacDocs/rep/tutorials/Tools.html), [isaac-xml-validator](https://wofsauge.github.io/isaac-xml-validator/) |

## Local Workflow Notes

- New collectible or trinket: add or update `ConchBlessing.ItemData` in `scripts/conch_blessing_items.lua`, then check `items.xml`, `ItemConfig`, and the relevant callback docs. If metadata affects XML, check whether `generate_xml.py` should regenerate `content/items.xml` or `content/itempools.xml`.
- New passive stat effect: set the item `cache` data, implement `MC_EVALUATE_CACHE`, and change player stat fields only inside cache evaluation.
- New active item effect: check `MC_USE_ITEM`, `MC_PRE_USE_ITEM`, `UseFlag`, `ActiveSlot`, and `items.xml` charge fields before choosing callback behavior.
- New familiar item: check `EntityPlayer:CheckFamiliar`, `CacheFlag.CACHE_FAMILIARS`, `EntityFamiliar`, and `MC_FAMILIAR_*` callbacks.
- New spawn or morph behavior: check `Isaac.Spawn`, `Game():Spawn`, `EntityPickup:Morph`, `Room:FindFreePickupSpawnPosition`, and the `EntityType` / variant enum pages.
- New room or floor transition behavior: prefer `MC_POST_NEW_ROOM`, `MC_POST_NEW_LEVEL`, `MC_POST_GAME_STARTED`, or `MC_PRE_GAME_EXIT` before considering broad per-frame callbacks.
- Save data: use `ConchBlessing.SaveManager` first. Use the Isaac save-data docs only to understand the underlying `Isaac.SaveModData` / `Isaac.LoadModData` behavior.
- Runtime entity state: use `Entity:GetData()` for temporary per-entity state, but never store entity userdata, sprite objects, RNG objects, or other userdata inside SaveManager tables.

## Search Tips

- Start with docs search or a web query like `site:wofsauge.github.io/IsaacDocs/rep EntityPlayer AddCacheFlags`.
- On large class pages, use browser search for the exact API name, for example `GetCollectibleNum`. The visible table of contents may split method words with dots, but the real API name is still the plain Lua method name.
- If a function signature links to enum types, open those enum pages immediately. Enum details often explain names used in XML or flags used by callbacks.
- If a page has `Bugs`, `Notes`, or `Version Difference` sections, treat those as part of the API contract for this mod.
- If a callback has optional entity-type or variant filtering, use it instead of checking every entity inside a broad callback.

## Common Cautions

- `Isaac.GetFrameCount()` and `Game():GetFrameCount()` are not interchangeable. Check the relevant page before using frame counts for timers.
- `Isaac.GetRoomEntities()` and `Isaac.FindByType()` are useful, but avoid repeated scans inside broad update callbacks unless the result is cached or the entity set is small.
- `items_metadata.xml` is usually not needed for this mod; quality and tags should generally live in `items.xml` data generated from `ConchBlessing.ItemData`.
- `itempools.xml` documentation is thin. For pool edits, compare against existing generated `content/itempools.xml`, the `ItemPoolType` enum, and in-game behavior.
- Search results can mix Repentance+, AB+, and old docs. Verify the URL contains `/rep/` before relying on a page.
