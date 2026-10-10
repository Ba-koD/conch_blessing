-- Visual review only. No inventory, pickup, room, seed or run mutations.
local Visuals = require("scripts.lib.upgrade_visuals")
local Locale = require("scripts.locale.init")
local Viewer = { index = 1 }
ConchBlessing.morphViewer = Viewer
local scene, previousIcon, nextIcon
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
    scene, previousIcon, nextIcon = nil, nil, nil
end
function Viewer.isRunning() return scene ~= nil end
Viewer.stop = stop

local function start(index)
    local testBench = package.loaded["scripts.dev.test_bench"]
    if testBench and testBench.isRunning() then
        log("Finish or stop conch_test before opening the visual viewer.")
        return false
    end
    if Game():GetNumPlayers() < 1 then log("Start a run first."); return false end
    local nextIndex = indexAt(index)
    local key = keyAt(nextIndex)
    local ok, result, before, after = pcall(function()
        local nextScene = Visuals.create(key, Game():GetRoom():GetCenterPos())
        local function iconAt(i)
            local item = ConchBlessing.ItemData[keyAt(i)]
            return Visuals.icon(item.type == "trinket" and PickupVariant.PICKUP_TRINKET
                or PickupVariant.PICKUP_COLLECTIBLE, item.id)
        end
        return nextScene, iconAt(nextIndex - 1), iconAt(nextIndex + 1)
    end)
    if not ok then
        stop()
        ConchBlessing.printError("[ConchMorph] Cannot open " .. key .. ": " .. tostring(result))
        return false
    end
    Viewer.index = nextIndex
    scene, previousIcon, nextIcon = result, before, after
    log(string.format("%d/%d %s | %s | R replay, arrows select, Backspace / conch_morph stop exit",
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
    local testBench = package.loaded["scripts.dev.test_bench"]
    if testBench and testBench.isRunning() then stop(); return end
    if scene.frame < scene.duration and not Visuals.safe(Visuals.update, scene) then stop() end
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
    if not Visuals.safe(Visuals.render, scene) then stop(); return end
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
if ModCallbacks.MC_POST_BACKDROP_PRE_RENDER_WALLS then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_BACKDROP_PRE_RENDER_WALLS, function()
        if scene and not Visuals.safe(Visuals.renderFloor, scene) then stop() end
    end)
end
ConchBlessing:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, stop)
ConchBlessing:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, stop)
ConchBlessing:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, stop)
return Viewer
