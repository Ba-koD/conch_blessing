local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Evolution preview: what a Magic Conch answer would turn a pickup into grows
-- out of it as a small tree of straight 1px lines, one stem per answer in the
-- Conch answer colours. A rotating pedestal grows a two-level tree: its
-- evolvable choices first, then each choice's results.
--
-- A tree grows up from the item. Where that would leave the screen or cover a
-- neighbour's tree, another pickup or the HUD, Preview.place turns it to the
-- side or below and pushes its results along their spread back onto the
-- screen (user choice 2026-11-14, docs/previews/evolution-edge-preview.html).
--
-- Pure presentation with standalone Sprites: no entity, no RNG, and the pickup
-- itself is never touched here. conch_blessing_highlight.lua decides when a
-- tree opens and owns the out-of-range hop. The upward layout and timing are
-- mirrored by docs/previews/evolution-branch-preview.html.
local View = require("scripts.lib.conch_answer_view")

local Preview = {}

local FLAGS = { "positive", "neutral", "negative" }
local TRUNK_RGB = { 0.92, 0.9, 0.86 }
local RESULT_SCALE, SOURCE_SCALE, LABEL_SCALE = 0.75, 0.5, 0.5
local RESULT_SPACING, GROUP_GAP = 26, 8
local RESULT_HALF, SOURCE_HALF = 12, 8 -- half of a 32px icon at each scale
local STAGGER = 2
-- Top of the item art above the entity position (vanilla 005.100/005.350
-- ANM2s): a pedestal item bobs up to 42px high, a shop item sits at 24px and a
-- trinket at 25px. The tree starts slightly inside that edge.
local ITEM_TOP = { pedestal = -40, shop = -22, trinket = -22 }
-- The other roots, from the same ANM2s: under the pedestal base, the shop
-- price and the trinket, and beside the middle of the item art (a pedestal
-- item spans -42..-6, a shop item -24..8, a trinket -25..7).
local ITEM_BOTTOM = { pedestal = 10, shop = 20, trinket = 9 }
local ITEM_SIDE = { pedestal = { 14, -24 }, shop = { 14, -8 }, trinket = { 10, -9 } }
-- What another tree must not cover: the item art with its pedestal or price.
local ART = { pedestal = { -14, -42, 14, 8 }, shop = { -14, -24, 14, 18 }, trinket = { -10, -25, 10, 7 } }
local EDGE = 3 -- kept clear along the screen's edges

-- Out-of-range cue, asking to be looked at: the item crouches and hops twice
-- in place in quick succession (7px, then 5px), landing squashed each time,
-- then rests as long as the two hops took and goes again (user requests
-- 2026-10-23: in place, never toward the player). Each key is
-- { dy, x scale, y scale }; whole pixels keep it crisp.
local HOP_KEYS = {
    { 0, 1.16, 0.84 },
    { -4, 0.88, 1.14 }, { -6, 0.94, 1.07 }, { -7, 1, 1 }, { -6, 1, 1 }, { -4, 0.96, 1.05 }, { -1, 0.92, 1.08 },
    { 0, 1.18, 0.82 },
    { -3, 0.9, 1.12 }, { -5, 0.96, 1.05 }, { -5, 1, 1 }, { -3, 0.96, 1.05 }, { -1, 0.94, 1.06 },
    { 0, 1.14, 0.86 }, { 0, 1.05, 0.95 },
}
Preview.HOP_LENGTH = #HOP_KEYS
Preview.HOP_PERIOD = 2 * Preview.HOP_LENGTH

--- The hop pose for a pickup's hop phase, or nil at rest.
function Preview.hop(phase)
    local key = HOP_KEYS[(phase or -1) + 1]
    if key then return { dy = key[1], sx = key[2], sy = key[3] } end
end

-- While fully open a spark runs up the branches to each result in turn, and
-- the result it reaches pops and flashes. The tree itself holds still.
local SPARK_EVERY, SPARK_SPEED = 30, 3
local POP_TICKS, POP_SCALE, POP_FLASH = 6, 0.18, 0.3

local function clamp(x) return math.max(0, math.min(1, x)) end
local function smooth(p) return p * p * (3 - 2 * p) end
local function easeOut(p) return 1 - (1 - p) ^ 3 end
local function backOut(p)
    local c, q = 1.70158, p - 1
    return 1 + (c + 1) * q * q * q + c * q * q
end
local function round(x) return math.floor(x + 0.5) end
local function progress(t, from, to) return clamp((t - from) / (to - from)) end

local function centred(count, centre)
    local xs = {}
    for i = 1, count do xs[i] = round(centre + (i - (count + 1) / 2) * RESULT_SPACING) end
    return xs
end

-- A straight segment from (x, y) in direction (dx, dy), drawn over the window.
local function addLine(layout, x, y, dx, dy, length, rgb, from, to)
    if length <= 0 then return end
    layout.lines[#layout.lines + 1] = { x = x, y = y, dx = dx, dy = dy, length = length, rgb = rgb, from = from, to = to }
end

-- A bar grows outward from the junction to both ends.
local function addBar(layout, x, y, left, right, from, to)
    addLine(layout, x, y, -1, 0, x - left, TRUNK_RGB, from, to)
    addLine(layout, x, y, 1, 0, right - x, TRUNK_RGB, from, to)
end

-- prefix: the route from the root to (junction, y) that a spark follows. The
-- stem below meets the bar at the junction; the results are centred on centre,
-- which differs from it only when they are pushed back onto the screen.
local function addResults(layout, results, junction, centre, y, start, prefix)
    local xs = centred(#results, centre)
    addBar(layout, junction, y, math.min(junction, xs[1]), math.max(junction, xs[#xs]), start, start + 5)
    for i, result in ipairs(results) do
        local rgb = View.colors[result.flag]
        local s = start + 3 + (i - 1) * STAGGER
        addLine(layout, xs[i], y, 0, -1, 4, rgb, s, s + 3)
        local path = {}
        for k, point in ipairs(prefix) do path[k] = point end
        path[#path + 1] = { junction, y }
        path[#path + 1] = { xs[i], y }
        path[#path + 1] = { xs[i], y - 4 }
        layout.icons[#layout.icons + 1] = {
            x = xs[i], y = y - 4 - RESULT_HALF, scale = RESULT_SCALE, half = RESULT_HALF,
            id = result.id, trinket = result.trinket == true, rgb = rgb, label = result.flag,
            from = s + 2, to = s + 9, path = path,
        }
        layout.openEnd = math.max(layout.openEnd, s + 9)
    end
end

-- The upward tree turned to grow another way. Sideways, the results stand in a
-- column with the first (positive) at the top.
local TURN = {
    up = function(x, y) return x, y end,
    down = function(x, y) return x, -y end,
    right = function(x, y) return -y, x end,
    left = function(x, y) return y, x end,
}

--- Geometry and timing relative to the tree's root.
--- groups: { { source = { id } | nil, results = { { flag, id, trinket } } } }.
--- One group without a source is a plain tree; otherwise every group hangs
--- below its source icon (a rotating pedestal's evolvable choice).
--- dir ("up" by default, "down", "left", "right") is the way it grows; shift
--- moves the results along their spread while the trunk stays at the item.
function Preview.layout(groups, tree, dir, shift)
    assert(type(groups) == "table" and #groups > 0, "evolution preview needs results")
    dir, shift = dir or "up", round(shift or 0)
    local turn = assert(TURN[dir], "unknown direction")
    local layout = { lines = {}, icons = {}, openEnd = 0, tree = tree == true, dir = dir, shift = shift }
    addLine(layout, 0, 0, 0, -1, 5, TRUNK_RGB, 0, 4)
    if not layout.tree then
        addResults(layout, groups[1].results, 0, shift, -5, 3, { { 0, 0 } })
    else
        local widths, total = {}, 0
        for i, group in ipairs(groups) do
            assert(group.source and #group.results > 0, "a tree group needs its source and results")
            widths[i] = (#group.results - 1) * RESULT_SPACING + 2 * RESULT_HALF
            total = total + widths[i] + (i > 1 and GROUP_GAP or 0)
        end
        local centres, x = {}, -total / 2 + shift
        for i, width in ipairs(widths) do
            centres[i] = round(x + width / 2)
            x = x + width + GROUP_GAP
        end
        addBar(layout, 0, -5, math.min(0, centres[1]), math.max(0, centres[#centres]), 3, 8)
        for i, group in ipairs(groups) do
            local c = centres[i]
            addLine(layout, c, -5, 0, -1, 4, TRUNK_RGB, 6, 9)
            layout.icons[#layout.icons + 1] = {
                x = c, y = -9 - SOURCE_HALF, scale = SOURCE_SCALE, half = SOURCE_HALF,
                id = group.source.id, trinket = false, rgb = TRUNK_RGB, from = 8, to = 14,
            }
            addLine(layout, c, -9 - 2 * SOURCE_HALF, 0, -1, 4, TRUNK_RGB, 13, 16)
            addResults(layout, group.results, c, c, -13 - 2 * SOURCE_HALF, 15,
                { { 0, 0 }, { 0, -5 }, { c, -5 }, { c, -9 - 2 * SOURCE_HALF } })
        end
    end
    if dir ~= "up" then
        for _, line in ipairs(layout.lines) do
            line.x, line.y = turn(line.x, line.y)
            line.dx, line.dy = turn(line.dx, line.dy)
        end
        for _, icon in ipairs(layout.icons) do
            icon.x, icon.y = turn(icon.x, icon.y)
            -- New points: the results of one group share their prefix's tables.
            if icon.path then
                local path = {}
                for k, point in ipairs(icon.path) do path[k] = { turn(point[1], point[2]) } end
                icon.path = path
            end
        end
    end
    return layout
end

--- What a pickup shows, as the roots and art boxes name it.
function Preview.kind(pickup)
    if pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE then
        local sprite = pickup:GetSprite()
        return sprite and sprite:GetAnimation() == "ShopIdle" and "shop" or "pedestal"
    end
    return "trinket"
end

--- The pickup's base on screen (its position with its sprite offset).
function Preview.base(pickup)
    local pos = Isaac.WorldToScreen(pickup.Position)
    local offset = pickup.SpriteOffset
    return round(pos.X + offset.X), round(pos.Y + offset.Y)
end

--- Where a tree growing dir starts, from a pickup's kind and base.
function Preview.root(kind, x, y, dir)
    dir = dir or "up"
    if dir == "up" then return x, y + ITEM_TOP[kind] end
    if dir == "down" then return x, y + ITEM_BOTTOM[kind] end
    local side = ITEM_SIDE[kind]
    return x + (dir == "right" and side[1] or -side[1]), y + side[2]
end

--- Root of the tree on screen: the top of the item art, or the side or the
--- base the placement chose.
function Preview.anchor(pickup, dir)
    local x, y = Preview.base(pickup)
    return Preview.root(Preview.kind(pickup), x, y, dir)
end

--- The item art (and pedestal or price) a pickup shows, on screen.
function Preview.artBox(kind, x, y)
    local a = ART[kind]
    return { x + a[1], y + a[2], x + a[3], y + a[4] }
end

--- Pose of each part at open time t (0 = closed, layout.openEnd = open).
function Preview.lineLength(line, t)
    return round(line.length * easeOut(progress(t, line.from, line.to)))
end
function Preview.iconPose(icon, t)
    local p = progress(t, icon.from, icon.to)
    return math.max(0, backOut(p)), smooth(p)
end

-- Standalone sprites, shared by every tree and rebuilt on reload.
local sprites, warned = {}, {}
local function warn(key, detail)
    if warned[key] then return end
    warned[key] = true
    ConchBlessing.printError("[EvolutionPreview] " .. key .. ": " .. tostring(detail))
end
local function loadSprite(key, path, sheet)
    if sprites[key] == nil then
        local ok, value = pcall(function()
            local s = Sprite()
            s:Load(path, true)
            if sheet then s:ReplaceSpritesheet(0, sheet); s:LoadGraphics() end
            s:SetFrame("Idle", 0)
            assert(not s.IsLoaded or s:IsLoaded(), "could not load " .. path)
            return s
        end)
        sprites[key] = ok and value or false
        if not ok then warn("ASSET_UNAVAILABLE", value) end
    end
    return sprites[key] or nil
end
local function pixel() return loadSprite("pixel", "gfx/effects/conch_upgrade_pixel.anm2") end
local function iconSprite(icon)
    local key = (icon.trinket and "T:" or "C:") .. tostring(icon.id)
    if sprites[key] == nil then
        local config = Isaac.GetItemConfig()
        local item = config and (icon.trinket and config:GetTrinket(icon.id) or config:GetCollectible(icon.id))
        if not item or not item.GfxFileName or item.GfxFileName == "" then
            sprites[key] = false
            warn("ICON_UNAVAILABLE", key)
        else
            return loadSprite(key, "gfx/effects/conch_upgrade_icon.anm2", item.GfxFileName)
        end
    end
    return sprites[key] or nil
end
function Preview.clearSprites() sprites, warned = {}, {} end

local function rect(s, x, y, w, h, color)
    s.Scale = Vector(w, h)
    s.Rotation = 0
    s.Color = color
    if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(s) end
    s:Render(Vector(x, y))
end

local function lineRect(line, length)
    local x, y = line.x, line.y
    if line.dx < 0 then return x - length, y, length, 1 end
    if line.dx > 0 then return x, y, length, 1 end
    if line.dy < 0 then return x, y - length, 1, length end
    return x, y, 1, length
end

-- Top-left of a result's label: beyond its icon in the way the tree grows
-- (above, below, or beside it), half its height h away from the icon edge.
local function labelSpot(dir, cx, cy, half, w, h)
    if dir == "down" then return cx - w / 2, cy + half + 1 end
    if dir == "right" then return cx + half + 2, cy - h / 2 end
    if dir == "left" then return cx - half - 2 - w, cy - h / 2 end
    return cx - w / 2, cy - half - 1 - h
end

--- Every part a fully open tree draws, as boxes { x0, y0, x1, y1 } around its
--- root: each line with its border, each icon at its largest pop, each label.
function Preview.parts(layout)
    local out, labels = {}, View.hasFont()
    for _, line in ipairs(layout.lines) do
        local x, y, w, h = lineRect(line, line.length)
        out[#out + 1] = { x - 1, y - 1, x + w + 1, y + h + 1 }
    end
    for _, icon in ipairs(layout.icons) do
        local h = icon.half * (icon.label and 1 + POP_SCALE or 1) + 1
        out[#out + 1] = { icon.x - h, icon.y - h, icon.x + h, icon.y + h }
        if icon.label and labels then
            local text = View.text("ui.conch_mode.flags." .. icon.label)
            local w, lh = View.width(text, LABEL_SCALE), View.lineHeight(LABEL_SCALE)
            local x, y = labelSpot(layout.dir, icon.x, icon.y, icon.half, w, lh)
            out[#out + 1] = { x - 1, y - 1, x + w + 1, y + lh + 1 }
        end
    end
    return out
end

local function bounds(parts, rx, ry)
    local b = { math.huge, math.huge, -math.huge, -math.huge }
    for _, p in ipairs(parts) do
        b[1], b[2] = math.min(b[1], rx + p[1]), math.min(b[2], ry + p[2])
        b[3], b[4] = math.max(b[3], rx + p[3]), math.max(b[4], ry + p[4])
    end
    return b
end
-- Boxes that only graze (a pedestal's shadow edge) do not count as covering.
local function overlaps(a, b)
    return a[1] < b[3] - 2 and b[1] < a[3] - 2 and a[2] < b[4] - 2 and b[2] < a[4] - 2
end
local function partsHit(parts, rx, ry, box)
    for _, p in ipairs(parts) do
        if overlaps({ rx + p[1], ry + p[2], rx + p[3], ry + p[4] }, box) then return true end
    end
    return false
end

--- Screen boxes of the HUD a tree should not cover, at the player's HUD
--- offset: active item, hearts, coins/bombs/keys, minimap, trinket and pocket
--- slots. Approximate by design; a tree only prefers to stay clear of them.
function Preview.hudBoxes(w, h, offset)
    offset = type(offset) == "number" and offset == offset and math.max(0, math.min(1, offset)) or 0
    local dx, dy = 20 * offset, 12 * offset
    return {
        { 4 + dx, 4 + dy, 36 + dx, 36 + dy },
        { 44 + dx, 6 + dy, 120 + dx, 34 + dy },
        { 4 + dx, 42 + dy, 34 + dx, 82 + dy },
        { w - 60 - dx, 4 + dy, w - 4 - dx, 48 + dy },
        { 4 + dx, h - 40 - dy, 40 + dx, h - 4 - dy },
        { w - 50 - dx, h - 40 - dy, w - 4 - dx, h - 4 - dy },
    }
end

--- Chooses how a pickup's tree grows (user choice 2026-11-14). It grows up
--- when that fits; otherwise a plain tree turns to the side away from its
--- nearest neighbour (else toward the roomier side), then the other side, then
--- down; a rotating pedestal's two-level tree, which would stand in a tall
--- column sideways, tries down before the sides. Each try pushes its results
--- along their spread to stay on screen, and a try is good when nothing leaves
--- the screen and no drawn part covers a box in scene.boxes (other pickups), a
--- part of a tree in scene.trees ({ parts, x, y }) or a box in scene.hud. When
--- no try is good the least bad wins: leaving the screen loses results and is
--- worst, covering another tree or item next, covering the HUD least (measured
--- 2026-11-14: in the top-left corner every other way brushed the HUD, and up
--- lost 24px). Without a scene it grows up.
--- scene = { w, h, boxes, trees, hud, neighbour = screen x | nil }.
--- Returns the layout, its root and its direction.
function Preview.place(groups, tree, kind, x, y, scene)
    if not scene or not scene.w or not scene.h then
        local rx, ry = Preview.root(kind, x, y, "up")
        return Preview.layout(groups, tree), rx, ry, "up"
    end
    local first
    if scene.neighbour then first = scene.neighbour > x and "left" or "right"
    else first = x < scene.w / 2 and "right" or "left" end
    local other = first == "left" and "right" or "left"
    local order = tree and { "up", "down", first, other } or { "up", first, other, "down" }
    local best
    for _, dir in ipairs(order) do
        local rx, ry = Preview.root(kind, x, y, dir)
        local layout = Preview.layout(groups, tree, dir, 0)
        local parts = Preview.parts(layout)
        local b = bounds(parts, rx, ry)
        local across = dir == "up" or dir == "down"
        local lo, hi, size = across and b[1] or b[2], across and b[3] or b[4], across and scene.w or scene.h
        local shift = 0
        if hi - lo > size - 2 * EDGE then shift = round(size / 2 - (lo + hi) / 2)
        elseif lo < EDGE then shift = math.ceil(EDGE - lo)
        elseif hi > size - EDGE then shift = math.floor(size - EDGE - hi) end
        if shift ~= 0 then
            -- Sideways the results' spread runs down the screen (the turn
            -- maps the upward x to y), so the same shift moves them there.
            layout = Preview.layout(groups, tree, dir, shift)
            parts = Preview.parts(layout)
            b = bounds(parts, rx, ry)
        end
        local off = math.max(0, -b[1]) + math.max(0, -b[2]) + math.max(0, b[3] - scene.w) + math.max(0, b[4] - scene.h)
        local hits, hud = 0, 0
        for _, box in ipairs(scene.boxes or {}) do
            if partsHit(parts, rx, ry, box) then hits = hits + 1 end
        end
        for _, other in ipairs(scene.trees or {}) do
            for _, p in ipairs(other.parts) do
                if partsHit(parts, rx, ry, { other.x + p[1], other.y + p[2], other.x + p[3], other.y + p[4] }) then
                    hits = hits + 1
                    break
                end
            end
        end
        for _, box in ipairs(scene.hud or {}) do
            if partsHit(parts, rx, ry, box) then hud = hud + 1 end
        end
        local cost = off * 1000 + hits * 100 + hud * 10
        if cost == 0 then return layout, rx, ry, dir end
        if not best or cost < best.cost then best = { layout = layout, x = rx, y = ry, dir = dir, cost = cost } end
    end
    return best.layout, best.x, best.y, best.dir
end

local function pathLength(path)
    local total = 0
    for k = 2, #path do
        total = total + math.abs(path[k][1] - path[k - 1][1]) + math.abs(path[k][2] - path[k - 1][2])
    end
    return total
end

--- Idle motion of a fully open tree at its own clock: where the spark is on
--- its way to the next result, or which result it has reached and pops.
function Preview.idle(layout, clock)
    local results = {}
    for _, icon in ipairs(layout.icons) do
        if icon.label then results[#results + 1] = icon end
    end
    if #results == 0 or not clock then return {} end
    local target = results[math.floor(clock / SPARK_EVERY) % #results + 1]
    local s, path = clock % SPARK_EVERY, target.path
    local total = pathLength(path)
    local travel = math.ceil(total / SPARK_SPEED)
    if s < travel then
        -- Its last step lands exactly under the result.
        local d = math.min(total, (s + 1) * SPARK_SPEED)
        for k = 2, #path do
            local a, b = path[k - 1], path[k]
            local length = math.abs(b[1] - a[1]) + math.abs(b[2] - a[2])
            if length > 0 and d <= length then
                local f = d / length
                return { spark = { x = round(a[1] + (b[1] - a[1]) * f), y = round(a[2] + (b[2] - a[2]) * f), rgb = target.rgb } }
            end
            d = d - length
        end
    elseif s < travel + POP_TICKS then
        local k = math.sin(math.pi * (s - travel + 1) / (POP_TICKS + 1))
        return { pop = { icon = target, scale = 1 + POP_SCALE * k, flash = POP_FLASH * k } }
    end
    return {}
end

--- Draws the tree rooted at (x, y) at open time t; clock drives the idle
--- motion once it is fully open. Returns what it drew.
function Preview.render(layout, x, y, t, clock)
    local drawn = { lines = 0, icons = 0, labels = 0, sparks = 0, pops = 0 }
    if t <= 0 then return drawn end
    local motion = clock and t >= layout.openEnd and Preview.idle(layout, clock) or {}
    local s = pixel()
    if s then
        local border, rects = Color(0, 0, 0, 0.6, 0, 0, 0), {}
        for _, line in ipairs(layout.lines) do
            local length = Preview.lineLength(line, t)
            if length > 0 then
                local lx, ly, w, h = lineRect(line, length)
                rects[#rects + 1] = { x + lx, y + ly, w, h, line.rgb }
            end
        end
        -- Every border first, then every core, so joints stay one clean line.
        for _, r in ipairs(rects) do rect(s, r[1] - 1, r[2] - 1, r[3] + 2, r[4] + 2, border) end
        for _, r in ipairs(rects) do
            rect(s, r[1], r[2], r[3], r[4], Color(r[5][1], r[5][2], r[5][3], 1, 0, 0, 0))
            drawn.lines = drawn.lines + 1
        end
        local spark = motion.spark
        if spark then
            rect(s, x + spark.x - 1, y + spark.y - 1, 3, 3, Color(spark.rgb[1], spark.rgb[2], spark.rgb[3], 0.6, 0, 0, 0))
            rect(s, x + spark.x, y + spark.y, 1, 1, Color(1, 1, 1, 1, 0, 0, 0))
            drawn.sparks = 1
        end
    end
    local labels = View.hasFont()
    for _, icon in ipairs(layout.icons) do
        local scale, alpha = Preview.iconPose(icon, t)
        local pop = motion.pop and motion.pop.icon == icon and motion.pop or nil
        if pop then scale = scale * pop.scale end
        local sprite = alpha > 0 and scale > 0 and iconSprite(icon)
        if sprite then
            local cx, cy = x + icon.x, y + icon.y
            sprite.Rotation = 0
            sprite.Scale = Vector(icon.scale * scale, icon.scale * scale)
            -- A flat answer-coloured silhouette one pixel around the item.
            sprite.Color = Color(0, 0, 0, alpha, icon.rgb[1], icon.rgb[2], icon.rgb[3])
            if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
            sprite:Render(Vector(cx + 1, cy))
            if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
            sprite:Render(Vector(cx - 1, cy))
            if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
            sprite:Render(Vector(cx, cy + 1))
            if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
            sprite:Render(Vector(cx, cy - 1))
            local flash = pop and pop.flash or 0
            sprite.Color = Color(1, 1, 1, alpha, flash, flash, flash)
            if ConchBlessing.AprilFools then ConchBlessing.AprilFools.Apply(sprite) end
            sprite:Render(Vector(cx, cy))
            drawn.icons = drawn.icons + 1
            if pop then drawn.pops = 1 end
            if icon.label and labels then
                local text = View.text("ui.conch_mode.flags." .. icon.label)
                local lx, ly = labelSpot(layout.dir, cx, cy, icon.half * scale, View.width(text, LABEL_SCALE), View.lineHeight(LABEL_SCALE))
                View.drawAt(text, round(lx), round(ly), LABEL_SCALE, icon.rgb, alpha)
                drawn.labels = drawn.labels + 1
            end
        end
    end
    return drawn
end

Preview.FLAGS = FLAGS
Preview._test = { centred = centred, ITEM_TOP = ITEM_TOP, RESULT_SPACING = RESULT_SPACING, HOP_KEYS = HOP_KEYS,
    SPARK_EVERY = SPARK_EVERY, POP_TICKS = POP_TICKS, pathLength = pathLength }
return Preview
