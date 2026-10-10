-- Real pickup review: only the viewer-owned pedestal is spawned/converted.
-- Presentation and morph timing come exclusively from the production queue.
local Visuals = require("scripts.lib.upgrade_visuals")
local Locale = require("scripts.locale.init")
-- Isaac exposes its own require, but not Lua's package/loaded table.
local TestBench = require("scripts.dev.test_bench")
local Viewer = { index = 1 }
ConchBlessing.morphViewer = Viewer
local scene, previousIcon, nextIcon
-- Keep ownership outside GetData: native morph/init callbacks may replace it.
-- EntityPtr can expire on native Morph as well as removal. Only the exact
-- transaction may rebind it synchronously after Morph; unrelated removals
-- must never adopt another pickup with matching subtype/seed/position.
local function ownedEntity(state)
    local entity = state and state.pickupPtr and state.pickupPtr.Ref
    if entity and entity:Exists() and GetPtrHash(entity) == state.pickupHash then return entity end
end
local function trackPickup(state, entity)
    local ok, err = pcall(function()
        state.pickupPtr = EntityPtr(entity)
        state.pickupHash = GetPtrHash(entity)
        assert(ownedEntity(state), "safe pickup reference unavailable")
    end)
    if not ok then
        -- Still in the spawn/Morph call: remove this exact entity before raising.
        -- Never retain a raw-reference fallback across frames.
        if entity and entity:Exists() then entity:Remove() end
        error(err, 0)
    end
end
local hudFont, fontAttempted
local function getFont()
    if not fontAttempted then
        fontAttempted = true
        local ok, result = pcall(function()
            local f = Font()
            f:Load("font/cjk/lanapixel.fnt")
            assert(f:IsLoaded() and f.DrawStringScaledUTF8 and f.GetStringWidthUTF8)
            return f
        end)
        if ok then hudFont = result end
    end
    return hudFont
end
local function label(key)
    return getFont() and Locale.text("ui.morph." .. key) or Locale.textIn("en", "ui.morph." .. key)
end
local function itemLabel(key)
    if getFont() then return Locale.text("items." .. key .. ".name") end
    return string.lower(key)
end
local function log(message)
    local text = "[ConchMorph] " .. message
    Isaac.DebugString(text)
    Isaac.ConsoleOutput(text .. "\n")
end
local function indexAt(index) return (index - 1) % #Visuals.catalog + 1 end
local function keyAt(index) return Visuals.catalog[indexAt(index)].key end
local function stop()
    local old = scene
    scene, previousIcon, nextIcon = nil, nil, nil
    if not old then return end
    local ok, err = pcall(function()
        if old.job then ConchBlessing.upgrade.cancel(old.job) end
        if old.pickup then ConchBlessing.template.cancelForPickup(old.pickup) end
    end)
    if not ok then ConchBlessing.printError("[ConchMorph] Cancel failed: " .. tostring(err)) end
    -- Removing the exact spawned entity is independent of queue cancellation,
    -- so a cosmetic failure cannot strand the real pickup in the room.
    ok, err = pcall(function()
        local entity = ownedEntity(old)
        if entity then entity:Remove() end
    end)
    if not ok then ConchBlessing.printError("[ConchMorph] Pickup cleanup failed: " .. tostring(err)) end
end
function Viewer.isRunning() return scene ~= nil end
function Viewer.ownsPickup(pickup)
    return ownedEntity(scene) ~= nil and pickup ~= nil and GetPtrHash(pickup) == scene.pickupHash
end
Viewer.stop = stop

local function start(index)
    if TestBench.isRunning() then
        log("Finish or stop conch_test before opening the visual viewer.")
        return false
    end
    if Game():GetNumPlayers() < 1 then log("Start a run first."); return false end
    if not ModCallbacks.MC_PRE_CHANGE_ROOM then
        log("Real pickup preview requires REPENTOGON's MC_PRE_CHANGE_ROOM cleanup hook.")
        return false
    end
    local nextIndex = indexAt(index)
    local key = keyAt(nextIndex)
    -- Native removal may remain in the spatial index until the next update.
    -- Re-searching immediately can push the next fixture off this pedestal's
    -- position. Selection/replay reuse the live fixture's exact location.
    local previous = ownedEntity(scene)
    local position = previous and Vector(previous.Position.X, previous.Position.Y)
    stop()
    local ok, err = pcall(function()
        assert(ConchBlessing.upgrade and ConchBlessing.upgrade.queuePickup, "upgrade transaction unavailable")
        local function iconAt(i)
            local item = ConchBlessing.ItemData[keyAt(i)]
            return Visuals.icon(item.type == "trinket" and PickupVariant.PICKUP_TRINKET
                or PickupVariant.PICKUP_COLLECTIBLE, item.id)
        end
        previousIcon, nextIcon = iconAt(nextIndex - 1), iconAt(nextIndex + 1)
        local variant, id = Visuals.origin(ConchBlessing.ItemData[key])
        assert(type(id) == "number" and id > 0 and Visuals.config(variant, id), "missing source item")
        local room = Game():GetRoom()
        local pos = position or room:FindFreePickupSpawnPosition(room:GetCenterPos(), 0, true)
        scene = { key = key, owner = Isaac.GetPlayer(0), sourceVariant = variant, sourceId = id, waiting = 0 }
        local entity = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, id, pos, Vector(0, 0), nil)
        trackPickup(scene, entity)
        local pickup = entity:ToPickup()
        assert(pickup and pickup.Variant == variant and pickup.SubType == id, "source spawn was replaced")
        scene.pickup = pickup
        -- Do not lend this demonstration to inventory, option groups or shops.
        pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice = 0, -1, false
        pickup.OptionsPickupIndex = 0
    end)
    if not ok then
        stop()
        ConchBlessing.printError("[ConchMorph] Cannot open " .. key .. ": " .. tostring(err))
        return false
    end
    Viewer.index = nextIndex
    log(string.format("%d/%d %s | REAL PICKUP | %s | R replay, arrows select, Backspace / conch_morph stop exit",
        nextIndex, #Visuals.catalog, string.lower(key),
        Visuals.isApplied(key) and "APPLIED" or "PENDING: current default animation"))
    return true
end
Viewer.start = start

ConchBlessing:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, command, params)
    if string.lower(command) ~= "conch_morph" then return end
    local parameter = (params or ""):match("^%s*(.-)%s*$")
    if parameter == "stop" then stop(); log("Stopped"); return end
    if parameter == "list" or parameter == "help" then
        log("conch_morph [item | list | stop]; R replay; arrows select; Backspace exit.")
        for _, row in ipairs(Visuals.catalog) do
            log(string.lower(row.key) .. (row.effect and " [APPLIED]" or " [PENDING / default]"))
        end
        return
    end
    if parameter == "" then start(Viewer.index); return end
    local key = Visuals.resolveKey(parameter)
    if not key then log("Unknown item: " .. parameter .. ". Use conch_morph list."); return end
    for index, row in ipairs(Visuals.catalog) do
        if key == row.key then start(index); return end
    end
end)

ConchBlessing:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if not scene or Game():IsPaused() then return end
    -- Starting another console suite releases input capture immediately.
    if TestBench.isRunning() then stop(); return end
    local ok, err = pcall(function()
        local entity = ownedEntity(scene)
        local pickup = entity and entity:ToPickup()
        assert(pickup, "preview pickup removed or replaced")
        if not scene.job then
            -- Let native pickup initialization finish, including provider init
            -- callbacks, before handing it to the ordinary upgrade transaction.
            scene.waiting = scene.waiting + 1
            assert(scene.waiting < 90, "source pickup initialization timed out")
            if pickup.FrameCount < 1 then return end
            assert(pickup.Variant == scene.sourceVariant and pickup.SubType == scene.sourceId, "source changed before upgrade")
            local job, reason = ConchBlessing.upgrade.queuePickup(pickup, scene.key, scene.owner)
            assert(job, reason)
            scene.job = job
            local owner = scene
            job.onPickupReinitialized = function(morphed)
                assert(scene == owner and owner.job == job, "stale preview transaction")
                local previousHash = owner.pickupHash
                local expired = not (owner.pickupPtr and owner.pickupPtr.Ref)
                trackPickup(owner, morphed)
                owner.pickup = morphed
                log("REBIND " .. string.lower(owner.key) .. " oldRef=" .. (expired and "expired" or "live")
                    .. " hash=" .. tostring(previousHash) .. "->" .. tostring(owner.pickupHash))
            end
            log("QUEUED " .. string.lower(scene.key) .. " source=" .. pickup.Variant .. ":" .. pickup.SubType)
        end
        local job = scene.job
        assert(job.status ~= "cancelled", "upgrade transaction cancelled")
        local visual = job.templateState.morphScene
        assert(not visual or not visual.failed, "upgrade renderer failed")
        if job.committed and not scene.reported then
            scene.reported = true
            local native = visual and visual.pickupVisual and visual.pickupVisual.released
            log("MORPH " .. string.lower(scene.key) .. " target=" .. pickup.Variant .. ":" .. pickup.SubType
                .. " itemRenderer=" .. (native and "native" or visual and "layer" or "native-default"))
        end
        if job.status == "complete" and not job.templateState.upgradeAnim and not scene.displayReported then
            scene.displayReported = true
            -- Property evidence after the shared template releases the pickup;
            -- this is not a claim that the final pixels were inspected.
            local observed, detail = pcall(function()
                local s = pickup:GetSprite()
                local name = pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and "head" or "body"
                local layer = s.GetLayer and s:GetLayer(name)
                local visible = layer and layer:IsVisible()
                local frame = layer and s.GetLayerFrameData and s:GetLayerFrameData(layer:GetLayerID())
                return string.format("alpha=%.3f scale=%.3f,%.3f entityVisible=%s layerVisible=%s frame=%s",
                    s.Color.A, s.Scale.X, s.Scale.Y, tostring(pickup.Visible),
                    layer and tostring(visible) or "unavailable", frame and "present" or "absent")
            end)
            log("DISPLAY " .. string.lower(scene.key) .. " "
                .. (observed and detail or "unavailable: " .. tostring(detail)))
        end
    end)
    if not ok then
        stop()
        ConchBlessing.printError("[ConchMorph] Viewer stopped: " .. tostring(err))
    end
end)

local function caption(text, x, y, r, g, b)
    local font = getFont()
    local width = font and font:GetStringWidthUTF8(text)
        or (Isaac.GetTextWidth and Isaac.GetTextWidth(text) or #text * 5)
    local left = x - width / 2
    local function write(dx, dy, red, green, blue)
        if font then
            font:DrawStringScaledUTF8(text, left + dx, y + dy, 1, 1,
                KColor(red, green, blue, 1), 0, true)
        else Isaac.RenderText(text, left + dx, y + dy, red, green, blue, 1) end
    end
    for _, delta in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        write(delta[1], delta[2], 0, 0, 0)
    end
    write(0, 0, r or 1, g or 1, b or 1)
end

local function renderViewer()
    if not scene then return end
    if not Game():IsPaused() then
        -- Raw keyboard edges are read on render, as required by Input's API.
        if Input.IsButtonTriggered(Keyboard.KEY_BACKSPACE, 0) then stop(); log("Stopped"); return end
        if Input.IsButtonTriggered(Keyboard.KEY_R, 0) then start(Viewer.index)
        elseif Input.IsButtonTriggered(Keyboard.KEY_LEFT, 0) or Input.IsButtonTriggered(Keyboard.KEY_UP, 0) then start(Viewer.index - 1)
        elseif Input.IsButtonTriggered(Keyboard.KEY_RIGHT, 0) or Input.IsButtonTriggered(Keyboard.KEY_DOWN, 0) then start(Viewer.index + 1) end
    end
    if not scene then return end
    local room = Game():GetRoom()
    local center = Isaac.WorldToScreen(room:GetCenterPos())
    local bottom = Isaac.WorldToScreen(room:GetBottomRightPos())
    local width = Isaac.GetScreenWidth and Isaac.GetScreenWidth() or center.X * 2
    local height = Isaac.GetScreenHeight and Isaac.GetScreenHeight() or bottom.Y + 30
    local x, y = width / 2, height - 57
    previousIcon:Render(Vector(x - 143, y - 25))
    nextIcon:Render(Vector(x + 143, y - 25))
    caption("< " .. itemLabel(keyAt(Viewer.index - 1)), x - 143, y - 7, 0.8, 0.8, 0.8)
    caption(itemLabel(keyAt(Viewer.index + 1)) .. " >", x + 143, y - 7, 0.8, 0.8, 0.8)
    caption(string.format("%d/%d  %s", Viewer.index, #Visuals.catalog, itemLabel(scene.key)), x, y - 42)
    caption(label(Visuals.isApplied(scene.key) and "applied" or "pending"), x, y - 28, 1, 0.82, 0.45)
    caption(label("controls"), x, y + 12)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not scene then return end
    local ok, err = pcall(renderViewer)
    if not ok then
        stop()
        ConchBlessing.printError("[ConchMorph] Viewer stopped: " .. tostring(err))
    end
end)

-- R must not also restart the run; arrows must not fire/move the player.
-- Other controls and all input while the viewer is closed are untouched.
local blocked = {}
for _, key in ipairs({ "ACTION_RESTART", "ACTION_LEFT", "ACTION_RIGHT", "ACTION_UP", "ACTION_DOWN",
    "ACTION_SHOOTLEFT", "ACTION_SHOOTRIGHT", "ACTION_SHOOTUP", "ACTION_SHOOTDOWN" }) do
    if ButtonAction[key] ~= nil then blocked[ButtonAction[key]] = true end
end
ConchBlessing:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, _, hook, action)
    if scene and blocked[action] then
        if hook == InputHook.GET_ACTION_VALUE then return 0 end
        return false
    end
end)
-- The real entity exists even after its morph. Keep just this fixture from
-- being acquired; normal room pickups retain their usual collision behaviour.
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup)
    if Viewer.ownsPickup(pickup) then return true end
end)
if ModCallbacks.MC_PRE_CHANGE_ROOM then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_CHANGE_ROOM, stop)
end
if ModCallbacks.MC_PRE_MOD_UNLOAD then
    ConchBlessing:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(_, mod)
        if mod == ConchBlessing or (ConchBlessing.originalMod and mod == ConchBlessing.originalMod) then stop() end
    end)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, stop)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, stop)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, stop)
return Viewer
