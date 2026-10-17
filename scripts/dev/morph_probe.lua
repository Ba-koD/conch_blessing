local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- conch_test morph: runs every applied upgrade presentation, plus one default
-- flag animation per flag and a rotating pedestal, through the real upgrade
-- transaction on a bench-owned pedestal, and checks what the engine actually did.
--
-- Oracles come from the approved presentation decisions recorded in AGENTS.md
-- and docs/previews/README.md (cue frames, volumes, pitches, hold/return
-- curves), not from the renderer's own tables. Pixels stay LOOK lines.
local TestBench = require("scripts.dev.test_bench")
local Visuals = require("scripts.lib.upgrade_visuals")

local Probe = {}
local PROJECT_SOUNDS = { "Conch Upgrade Thunder Strike", "Conch Upgrade Rain", "Conch Upgrade Clock Tick",
    "Conch Upgrade Clock Tock", "Conch Upgrade Clock Bell" }
-- One pending (default animation) item per Magic Conch flag.
local DEFAULT_KEYS = { positive = "LIVE_EYE", neutral = "ROUND", negative = "FLOOR" }
local DEFAULT_SOUND = { positive = "SOUND_HOLY", neutral = "SOUND_POWERUP_SPEWER", negative = "SOUND_POWERUP_SPEWER" }

local LOOK = {
    lightning = "the room darkens around the item, stays dark, then one close bolt strikes as it changes and the darkness clears",
    saturn = "three pets fade in already riding the tilted ring, speed up and close in while the item turns black, fuse into a golden ring, collapse, and the new item slowly regains its colours",
    rain = "rain falls across a flooding floor, five drops soak the item blue, it changes and dries",
    clock = "the clock runs six hours from 6 to 12 with a continuous tick-tock, a heavy grandfather-clock strike at 12 as the item changes; nothing else beside it",
    fire = "a red flame ignites above the item, grows down over it, bursts and the new item appears",
    ice = "a blue flame ignites above the item, grows down over it, freezes and the new item appears",
    missile = "a red reticle with the lock-on beeping, a rocket falls and explodes on the item",
    void = "dark smoke motes swirl inward without fading, then vanish together as it changes",
    purify = "a halo settles, smoke burns away, the crown turns white, holy light and three glints",
    neglect = "the left half of the screen slowly turns black with a soft edge at the middle, the item changes while it is dark, and the left half slowly returns",
}

-- Expected cue schedule per effect: { sound name, scheduled frame, volume, pitch }.
local function expectedCues(effect, impact)
    local list = {}
    local function add(sound, at, volume, pitch)
        list[#list + 1] = { sound = sound, at = at, volume = volume, pitch = pitch or 1, order = #list }
    end
    if effect == "lightning" then
        add("SOUND_THUNDER", 2, 1, 0.65)
        add("Conch Upgrade Thunder Strike", impact, 1)
    elseif effect == "saturn" then
        add("SOUND_MOTHER_SPIN_START", 56, 1)
        add("SOUND_SUMMONSOUND", impact, 1)
    elseif effect == "fire" or effect == "ice" then
        add("SOUND_CANDLE_LIGHT", 5, 0.8)
        add("SOUND_FLAME_BURST", impact - 7, 1)
        if effect == "ice" then add("SOUND_FREEZE", impact, 1) end
    elseif effect == "missile" then
        add("SOUND_DR_REMOTE_WARNING", 3, 1)
        add("SOUND_ROCKET_LAUNCH", impact - 16, 0.8)
        add("SOUND_ROCKET_EXPLOSION", impact, 1)
    elseif effect == "purify" then
        add("SOUND_ANGEL_WING", 18, 1)
        add("SOUND_HOLY", impact, 1)
    end
    if effect == "rain" then add("Conch Upgrade Rain", 5, 1) end
    if effect and effect:find("clock", 1, true) then
        -- 6:00 to 12:00: one 째깍 per minute turn, evenly from frame 0 to the
        -- change: 째 (Tick) as the hand passes 6, 깍 (Tock) as it reaches 12.
        for j = 1, 12 do
            add(j % 2 == 1 and "Conch Upgrade Clock Tick" or "Conch Upgrade Clock Tock",
                math.floor(impact * j / 12 + 0.5), 1)
        end
        -- 댕: the bell strikes 12 together with the change, after the last 깍.
        add("Conch Upgrade Clock Bell", impact, 1)
    end
    table.sort(list, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.order < b.order
    end)
    return list
end
Probe.expectedCues = expectedCues

local function near(a, b, tolerance) return type(a) == "number" and math.abs(a - b) <= (tolerance or 1e-6) end

local function livePickup(ctx)
    local fixture = ctx.fixture
    local entity = fixture and fixture.ptr and fixture.ptr.Ref
    if entity and entity:Exists() and GetPtrHash(entity) == fixture.hash then return entity:ToPickup() end
end

local function removeFixture(ctx)
    if ctx.job and ctx.job.status ~= "complete" and ctx.job.status ~= "cancelled" then
        ConchBlessing.upgrade.cancel(ctx.job)
    end
    local pickup = livePickup(ctx)
    if pickup then pickup:Remove() end
    -- Every stage proves its own evidence; nothing carries into the next one.
    ctx.job, ctx.scene, ctx.fixture, ctx.defaultAnim, ctx.defaultHeard = nil, nil, nil, nil, nil
    ctx.colorTrail = nil
end
Probe._removeFixture = removeFixture

local function colorParts(c)
    return { c.R, c.G, c.B, c.A, c.RO, c.GO, c.BO }
end
-- The eligibility highlight pulses a pedestal's colour on its own schedule.
-- Like the real queue, read the pedestal's own colour with that pulse released.
local function nativeColor(pickup)
    local highlight = ConchBlessing.UpgradeHighlight
    if highlight and type(highlight.StopForPickup) == "function" then highlight.StopForPickup(pickup) end
    return colorParts(pickup:GetSprite().Color)
end

-- Spawn the origin pedestal, wait for native init, and queue the real upgrade.
local function startUpgrade(plan, key)
    plan.act(function(player, ctx)
        removeFixture(ctx)
        local item = assert(ConchBlessing.ItemData[key], "unknown item " .. key)
        local variant, id = Visuals.origin(item)
        local room = Game():GetRoom()
        ctx.fixturePos = ctx.fixturePos or room:FindFreePickupSpawnPosition(room:GetCenterPos() + Vector(0, -60), 0, true)
        -- Stand well away so the converted pedestal is never collected.
        player.Position = room:GetCenterPos() + Vector(0, 110)
        player.Velocity = Vector(0, 0)
        local entity = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, id, ctx.fixturePos, Vector(0, 0), nil)
        ctx.fixture = { ptr = EntityPtr(entity), hash = GetPtrHash(entity), key = key }
        local pickup = assert(entity:ToPickup(), "origin is not a pickup")
        pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice, pickup.OptionsPickupIndex = 0, -1, false, 0
        ctx.sourceVariant, ctx.sourceId = variant, id
    end)
    plan.waitUntil(function(_, ctx)
        local pickup = livePickup(ctx)
        return pickup ~= nil and pickup.FrameCount >= 1, "origin pedestal missing or not initialized"
    end, 60, key .. ": origin pedestal initialized")
    plan.act(function(player, ctx)
        local pickup = assert(livePickup(ctx), "origin pedestal disappeared")
        assert(pickup.Variant == ctx.sourceVariant and pickup.SubType == ctx.sourceId, "origin changed before the upgrade")
        ctx.originalColor = nativeColor(pickup)
        local job, reason = ConchBlessing.upgrade.queuePickup(pickup, key, player)
        assert(job, "queue refused: " .. tostring(reason))
        ctx.job = job
        job.onPickupReinitialized = function(morphed)
            ctx.fixture.ptr, ctx.fixture.hash = EntityPtr(morphed), GetPtrHash(morphed)
        end
    end)
end

local function waitForCompletion(plan, key, timeout)
    plan.waitUntil(function(_, ctx)
        local job = ctx.job
        local live = livePickup(ctx)
        if live then
            ctx.colorTrail = ctx.colorTrail or {}
            ctx.colorTrail[#ctx.colorTrail + 1] = colorParts(live:GetSprite().Color)
        end
        ctx.scene = ctx.scene or job.templateState.morphScene
        if job.templateState.upgradeAnim and not ctx.defaultAnim then ctx.defaultAnim = job.templateState.upgradeAnim end
        if job.status == "cancelled" then return true end
        return job.status == "complete" and not job.templateState.upgradeAnim,
            "job=" .. tostring(job.status) .. " committed=" .. tostring(job.committed == true)
    end, timeout, key .. ": upgrade transaction and presentation finish")
end

local function commonChecks(plan, key)
    local item = ConchBlessing.ItemData[key]
    plan.check(key .. ": converts the pedestal to its target item", function(_, ctx)
        local pickup = livePickup(ctx)
        if not pickup then return false, "converted pedestal missing" end
        local wantVariant = item.type == "trinket" and PickupVariant.PICKUP_TRINKET or PickupVariant.PICKUP_COLLECTIBLE
        local subType = wantVariant == PickupVariant.PICKUP_TRINKET and pickup.SubType % 32768 or pickup.SubType
        return ctx.job.status == "complete" and pickup.Variant == wantVariant and subType == item.id,
            string.format("status=%s got %d:%d want %d:%d", tostring(ctx.job.status), pickup.Variant, subType, wantVariant, item.id)
    end)
    plan.check(key .. ": restores the pedestal's original colour", function(_, ctx)
        local pickup = livePickup(ctx)
        if not pickup then return false, "converted pedestal missing" end
        local now, before = nativeColor(pickup), ctx.originalColor
        for i = 1, 7 do
            if not near(now[i], before[i], 1e-3) then
                return false, string.format("component %d: got %.3f want %.3f", i, now[i], before[i])
            end
        end
        return true, string.format("R,G,B,A=%.2f,%.2f,%.2f,%.2f", now[1], now[2], now[3], now[4])
    end)
    plan.check(key .. ": item layer and pedestal visible afterwards", function(_, ctx)
        local pickup = livePickup(ctx)
        if not pickup then return false, "converted pedestal missing" end
        local s = pickup:GetSprite()
        if type(s.GetLayer) ~= "function" then return nil, "Sprite:GetLayer unavailable" end
        local layer = s:GetLayer(pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and "head" or "body")
        local visible = layer and layer:IsVisible()
        return pickup.Visible and visible == true and near(s.Color.A, ctx.originalColor[4], 1e-3),
            string.format("entityVisible=%s layerVisible=%s alpha=%.3f", tostring(pickup.Visible), tostring(visible), s.Color.A)
    end)
end

-- Every listed frame must carry a sample, and fn(value, frame) must hold.
local function sampled(scene, name, first, last, fn)
    local values = scene.samples[name]
    if not values then return false, "no " .. name .. " samples were drawn" end
    for f = first, last do
        if values[f] == nil then return false, string.format("%s not drawn at frame %d", name, f) end
        local ok, why = fn(values[f], f)
        if not ok then return false, string.format("%s=%.3f at frame %d: %s", name, values[f], f, why or "") end
    end
    return true, string.format("%s frames %d-%d", name, first, last)
end

-- Largest change of any colour channel between two consecutive frames that
-- still reads as gradual (a snap back to the original is 0.3 or more).
local MAX_COLOR_STEP = 0.08
local function colorTrail(values, first, last)
    local worst, at, previous = 0, nil, nil
    for f = first, last do
        local c = values[f]
        if c == nil then return nil, "no colour at frame " .. f end
        if previous then
            for i = 1, 7 do
                local step = math.abs(c[i] - previous[i])
                if step > worst then worst, at = step, f end
            end
        end
        previous = c
    end
    return worst, at
end
Probe.MAX_COLOR_STEP = MAX_COLOR_STEP
Probe.colorTrail = colorTrail

local function effectChecks(plan, key, profile)
    local effect, impact = profile.effect, profile.impact
    local duration = profile.duration or 102
    if effect == "lightning" then
        plan.check(key .. ": darkness rises, holds at full until the strike and clears on it", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "darkness", 18, impact - 1, function(v) return near(v, 0.88, 0.005), "should hold 0.88" end)
            if not ok then return ok, detail end
            ok, detail = sampled(s, "darkness", impact, impact + 3, function(v) return v == 0, "should be cleared" end)
            if not ok then return ok, detail end
            return sampled(s, "darkness", 3, 17, function(v, f)
                return v > 0 and v <= 0.88 and (f == 3 or v >= s.samples.darkness[f - 1]), "should rise"
            end)
        end)
        plan.check(key .. ": the engine draws the result item from the commit (native result)", function(_, ctx)
            local view = ctx.scene.pickupVisual
            return view ~= nil and view.released == true, "pickupVisual.released=" .. tostring(view and view.released)
        end)
    elseif effect == "saturn" then
        plan.check(key .. ": three stand-in pets ride the ring in a run without familiars", function(_, ctx)
            local s = ctx.scene
            return #s.pets == 3 and s.petSource == "random", string.format("pets=%d source=%s", #s.pets, tostring(s.petSource))
        end)
        plan.check(key .. ": the item darkens to black only from frame 70 up to the change", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "black", 1, 70, function(v) return v == 0, "should not be dark yet" end)
            if not ok then return ok, detail end
            return sampled(s, "black", 71, impact - 1, function(v, f)
                return v > 0 and v >= s.samples.black[f - 1] and (f < impact - 1 or v >= 0.95), "should deepen to near black"
            end)
        end)
        plan.check(key .. ": the colour returns gradually over 45 frames, not at once", function(_, ctx)
            local s, maxStep = ctx.scene, 0
            local ok, detail = sampled(s, "black", impact, impact + 45, function(v, f)
                if f == impact then return v >= 0.99, "should start fully black" end
                local step = s.samples.black[f - 1] - v
                maxStep = math.max(maxStep, step)
                return step >= -1e-9 and step <= 0.05, "should fall by at most 0.05 per frame"
            end)
            if not ok then return ok, detail end
            return s.samples.black[impact + 45] <= 0.01, string.format("%s; max step %.3f; final %.3f", detail, maxStep, s.samples.black[impact + 45])
        end)
    elseif effect == "rain" then
        plan.check(key .. ": the item soaks blue up to the change, then dries gradually over 45 frames", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "wet", 2, impact - 1, function(v, f)
                return v >= (s.samples.wet[f - 1] or v) - 1e-9 and (f < impact - 1 or v >= 0.99), "should keep soaking"
            end)
            if not ok then return ok, detail end
            ok, detail = sampled(s, "wet", impact, impact + 45, function(v, f)
                if f == impact then return v >= 0.99, "the result should start as wet as the original ended" end
                local step = s.samples.wet[f - 1] - v
                return step >= -1e-9 and step <= 0.05, "should dry by at most 0.05 per frame"
            end)
            if not ok then return ok, detail end
            return sampled(s, "wet", impact + 45, duration, function(v) return v == 0, "should be fully dry" end)
        end)
        plan.check(key .. ": the flood overlay draws on the floor pass", function(_, ctx)
            if not ModCallbacks.MC_PRE_BACKDROP_RENDER_WATER then return nil, "MC_PRE_BACKDROP_RENDER_WATER unavailable; rain and ripples only" end
            local s = ctx.scene
            return #s.floorCells > 0 and s.floorRenders > 0, string.format("cells=%d floorRenders=%d drops=%d", #s.floorCells, s.floorRenders, #(s.drops or {}))
        end)
    elseif effect == "void" then
        plan.check(key .. ": motes keep their density until the change, then vanish within 3 frames", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "vanish", 1, impact, function(v) return v == 0, "should not fade before the change" end)
            if not ok then return ok, detail end
            return sampled(s, "vanish", impact + 3, impact + 5, function(v) return v == 1, "should be gone" end)
        end)
    elseif effect == "fire" or effect == "ice" then
        plan.check(key .. ": the flame conceals the item before the change and reveals the result", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "itemAlpha", 1, 24, function(v) return v == 1, "should be fully visible" end)
            if not ok then return ok, detail end
            ok, detail = sampled(s, "itemAlpha", impact - 1, impact, function(v) return v < 0.05, "should be concealed" end)
            if not ok then return ok, detail end
            return sampled(s, "itemAlpha", 68, 72, function(v) return v == 1, "result should be revealed" end)
        end)
    elseif effect and effect:find("clock", 1, true) then
        plan.check(key .. ": the clock runs six hours from 6:00 to 12:00 at a constant fast speed, one tick-tock per turn", function(_, ctx)
            local s = ctx.scene
            local speed = 2160 / impact
            local ok, detail = sampled(s, "minute", 2, impact, function(v, f)
                return near(v - s.samples.minute[f - 1], speed, 1e-6), string.format("should turn a constant %.1f degrees per frame", speed)
            end)
            if not ok then return ok, detail end
            -- 째 as the minute hand passes 6 (half turns), 깍 as it reaches 12.
            for j = 1, 12 do
                local at = math.floor(impact * j / 12 + 0.5)
                local minute, hour = s.samples.minute[at], s.samples.hour[at]
                if not (near(minute, 180 * j, 0.5) and near(hour, 180 + 15 * j, 0.05)) then
                    return false, string.format("beat %d at frame %d: minute=%.1f hour=%.1f", j, at, minute or -1, hour or -1)
                end
            end
            return speed >= 20, string.format("12:00 at the change; minute hand %.1f degrees per frame", speed)
        end)
    elseif effect == "neglect" then
        plan.check(key .. ": the left half darkens gradually to black, holds through the change and returns gradually", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "neglect", 7, 42, function(v, f)
                local step = v - s.samples.neglect[f - 1]
                return step >= -1e-9 and step <= 0.08, "should darken by at most 0.08 per frame"
            end)
            if not ok then return ok, detail end
            ok, detail = sampled(s, "neglect", 42, impact, function(v) return near(v, 1, 1e-9), "should be fully black" end)
            if not ok then return ok, detail end
            ok, detail = sampled(s, "neglect", impact + 1, impact + 45, function(v, f)
                local step = s.samples.neglect[f - 1] - v
                return step >= -1e-9 and step <= 0.05, "should return by at most 0.05 per frame"
            end)
            if not ok then return ok, detail end
            return sampled(s, "neglect", impact + 45, duration, function(v) return v == 0, "should be fully visible" end)
        end)
        plan.check(key .. ": only the left half of the screen is covered", function(_, ctx)
            local width = Isaac.GetScreenWidth and Isaac.GetScreenWidth()
            if not width then return nil, "Isaac.GetScreenWidth unavailable" end
            local mid = ctx.scene.neglectMid
            return mid ~= nil and near(mid, width / 2, 0.5), string.format("edge at x=%s for a %d px wide screen", tostring(mid), width)
        end)
    elseif effect == "purify" then
        plan.check(key .. ": the crown whitens fully, then returns to its colours before the end", function(_, ctx)
            local s = ctx.scene
            local ok, detail = sampled(s, "white", 38, impact + 8, function(v) return near(v, 1, 1e-6), "should be fully white" end)
            if not ok then return ok, detail end
            return sampled(s, "white", duration - 8, duration, function(v) return near(v, 0, 1e-6), "should be back to colour" end)
        end)
    end
end

local function stageApplied(plan, key)
    local profile = Visuals.profile(key)
    local effect, impact = profile.effect, profile.impact
    local duration = profile.duration or 102
    plan.section("morph " .. string.lower(key) .. " (" .. effect .. ")", LOOK[effect])
    startUpgrade(plan, key)
    plan.waitUntil(function(_, ctx)
        ctx.scene = ctx.job.templateState.morphScene
        return ctx.scene ~= nil, "applied presentation did not start (fell back to the flag animation?)"
    end, 5, key .. ": applied presentation starts")
    waitForCompletion(plan, key, duration + 120)
    commonChecks(plan, key)
    plan.check(key .. ": presentation ran to its last frame", function(_, ctx)
        local s = ctx.scene
        return s.endReason == "after:complete" and s.endFrame == duration and not s.failed,
            string.format("end=%s frame=%s duration=%d failed=%s", tostring(s.endReason), tostring(s.endFrame), duration, tostring(s.failed == true))
    end)
    plan.check(key .. ": every frame from 1 to the end was drawn", function(_, ctx)
        local missing = {}
        for f = 1, duration do if not ctx.scene.rendered[f] and #missing < 10 then missing[#missing + 1] = f end end
        return #missing == 0, #missing == 0 and ("frames 1-" .. duration .. "; frame0=" .. tostring(ctx.scene.rendered[0] ~= nil))
            or "missing " .. table.concat(missing, ",")
    end)
    plan.check(key .. ": every milestone was reached exactly on its frame", function(_, ctx)
        local s, late = ctx.scene, {}
        for _, m in ipairs(Visuals.milestones(s)) do
            if s.marks[m.name] ~= m.frame then late[#late + 1] = m.name .. "@" .. tostring(s.marks[m.name]) .. "/" .. m.frame end
        end
        return #late == 0, #late == 0 and (#Visuals.milestones(s) .. " milestones") or table.concat(late, " ")
    end)
    plan.check(key .. ": every cue played once, on its frame, at its volume and pitch", function(_, ctx)
        local want, got = expectedCues(effect, impact), ctx.scene.cues
        if #got ~= #want then
            local names = {}
            for _, cue in ipairs(got) do names[#names + 1] = Visuals.cueName(cue) .. "@" .. cue.frame end
            return false, string.format("played %d cues, want %d: %s", #got, #want, table.concat(names, " "))
        end
        for i, w in ipairs(want) do
            local c = got[i]
            local name = Visuals.cueName(c)
            if name ~= w.sound or c.at ~= w.at or c.frame ~= w.at or not near(c.volume, w.volume) or not near(c.pitch, w.pitch) then
                return false, string.format("cue %d: got %s at=%d frame=%d vol=%.2f pitch=%.2f want %s at=%d vol=%.2f pitch=%.2f",
                    i, name, c.at, c.frame, c.volume, c.pitch, w.sound, w.at, w.volume, w.pitch)
            end
        end
        return true, #want .. " cues"
    end)
    plan.check(key .. ": the engine started every cue (SFXManager:IsPlaying)", function(_, ctx)
        local silent = {}
        for _, cue in ipairs(ctx.scene.cues) do
            if not cue.heard then silent[#silent + 1] = Visuals.cueName(cue) .. "@" .. cue.frame .. "(" .. tostring(cue.now) .. "/" .. tostring(cue.next) .. ")" end
        end
        if #ctx.scene.cues == 0 then return true, "this presentation has no cues" end
        return #silent == 0, #silent == 0 and (#ctx.scene.cues .. " cues playing") or "not playing: " .. table.concat(silent, " ")
    end)
    plan.check(key .. ": the item's colour changes gradually and ends on its own colour", function(_, ctx)
        local tint = ctx.scene.samples.tint
        if not tint then return false, "no item colour was drawn" end
        local worst, at = colorTrail(tint, 1, duration)
        if not worst then return false, at end
        local final, identity = tint[duration], { 1, 1, 1, 1, 0, 0, 0 }
        for i = 1, 7 do
            if not near(final[i], identity[i], 1e-6) then
                return false, string.format("last frame still tinted (channel %d = %.3f)", i, final[i])
            end
        end
        return worst <= MAX_COLOR_STEP, string.format("largest step %.3f at frame %s", worst, tostring(at))
    end)
    effectChecks(plan, key, profile)
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

local function stageDefault(plan, flag)
    local key = DEFAULT_KEYS[flag]
    plan.section("default " .. flag .. " animation (" .. string.lower(key) .. ")",
        flag == "positive" and "the item brightens white with the Holy Light, changes and fades back"
        or flag == "neutral" and "the item greys out, changes and regains its colour"
        or "the item darkens red, changes and regains its colour")
    startUpgrade(plan, key)
    plan.waitUntil(function(_, ctx)
        local anim = ctx.job.templateState.upgradeAnim
        if anim then ctx.defaultAnim = anim end
        return anim ~= nil, "default animation did not start"
    end, 5, key .. ": default animation starts")
    plan.check(key .. ": uses the flag animation, not an applied presentation", function(_, ctx)
        return ctx.job.templateState.morphScene == nil and ctx.defaultAnim.type == flag,
            "type=" .. tostring(ctx.defaultAnim.type)
    end)
    plan.waitUntil(function(_, ctx)
        local id = SoundEffect[DEFAULT_SOUND[flag]]
        ctx.defaultHeard = ctx.defaultHeard or (id ~= nil and SFXManager():IsPlaying(id))
        return ctx.defaultHeard, DEFAULT_SOUND[flag] .. " is not playing"
    end, 3, key .. ": the default " .. DEFAULT_SOUND[flag] .. " cue is playing")
    waitForCompletion(plan, key, 200)
    commonChecks(plan, key)
    plan.check(key .. ": the colour eases in, holds through the change and eases back", function(_, ctx)
        local trail = ctx.colorTrail or {}
        if #trail < 100 then return false, "only " .. #trail .. " colour samples" end
        local worst, at = colorTrail(trail, 1, #trail)
        if not worst then return false, at end
        local final = trail[#trail]
        for i = 1, 7 do
            if not near(final[i], ctx.originalColor[i], 1e-3) then
                return false, string.format("ended on channel %d = %.3f, want %.3f", i, final[i], ctx.originalColor[i])
            end
        end
        return worst <= MAX_COLOR_STEP, string.format("%d updates; largest step %.3f at update %s", #trail, worst, tostring(at))
    end)
    plan.act(function(_, ctx) removeFixture(ctx) end)
end

-- A rotating pedestal (REPENTOGON collectible cycle) keeps turning its choices
-- while the upgrade plays. DIAG lines record what a native turn does to the
-- pickup (reference, GetData, seed, Morph callbacks); the checks require the
-- real transaction to convert the matching choice and keep the whole circle.
local CYCLE_KEY = "LIVE_EYE" -- Dead Eye -> Live Eye, the default positive animation
local CYCLE_PROBE_KEY = "__ConchBlessingCycleProbe"
local morphWatch = nil -- Morph callbacks seen for the fixture: { hash, post }
if ModCallbacks.MC_PRE_PICKUP_MORPH and ModCallbacks.MC_POST_PICKUP_MORPH then
    ConchBlessing:AddCallback(ModCallbacks.MC_POST_PICKUP_MORPH, function(_, pickup)
        if morphWatch and GetPtrHash(pickup) == morphWatch.hash then morphWatch.post = morphWatch.post + 1 end
    end)
end

local function circleOf(pickup)
    local ids = { pickup.SubType }
    for _, id in ipairs(pickup:GetCollectibleCycle()) do ids[#ids + 1] = id end
    return ids
end

local function sameCircle(a, b)
    if #a ~= #b then return false end
    for offset = 0, #a - 1 do
        local same = true
        for i = 1, #a do
            if a[i] ~= b[(i + offset - 1) % #b + 1] then same = false; break end
        end
        if same then return true end
    end
    return false
end

-- Record every native turn of the fixture: the shown choice changed without
-- the transaction's own commit. The bench follows its own spawn wrapper.
local function trackTurns(ctx)
    local w = ctx.wheel
    local p = w.entity
    if not p:Exists() or GetPtrHash(p) ~= w.hash then return end
    ctx.fixture.ptr = EntityPtr(p)
    local committed = ctx.job ~= nil and ctx.job.committed == true
    if committed and not w.sawCommit then
        -- The commit's own Morph changed the head; start again from it.
        w.sawCommit = true
        w.head, w.ptr = p.SubType, EntityPtr(p)
        p:GetData()[CYCLE_PROBE_KEY] = w.token
        return
    end
    if p.SubType == w.head then return end
    local frame = Game():GetFrameCount()
    w.turns[#w.turns + 1] = {
        gap = w.at and frame - w.at or nil,
        ptr = w.ptr.Ref ~= nil,
        data = p:GetData()[CYCLE_PROBE_KEY] == w.token,
        seed = p.InitSeed == w.seed,
        morphs = morphWatch and morphWatch.post - w.post or 0,
        circle = sameCircle(circleOf(p), committed and w.target or w.source),
        committed = committed,
        locked = not committed and ctx.job ~= nil and ConchBlessing.upgrade.isAnimatingPickup(p) or nil,
    }
    w.head, w.at, w.ptr, w.post = p.SubType, frame, EntityPtr(p), morphWatch and morphWatch.post or 0
    p:GetData()[CYCLE_PROBE_KEY] = w.token
end

local function turnsWhere(ctx, test)
    local n = 0
    for _, turn in ipairs(ctx.wheel.turns) do if test(turn) then n = n + 1 end end
    return n
end

local function stageCycle(plan)
    local key = CYCLE_KEY
    local item = ConchBlessing.ItemData[key]
    plan.section("rotating pedestal (" .. string.lower(key) .. ")",
        "the pedestal keeps turning between Dead Eye, Sad Onion and Inner Eye; Dead Eye turns into Live Eye with the white flash while the pedestal keeps turning")
    plan.act(function(player, ctx)
        removeFixture(ctx)
        local variant, id = Visuals.origin(item)
        local room = Game():GetRoom()
        ctx.fixturePos = ctx.fixturePos or room:FindFreePickupSpawnPosition(room:GetCenterPos() + Vector(0, -60), 0, true)
        player.Position = room:GetCenterPos() + Vector(0, 110)
        player.Velocity = Vector(0, 0)
        local entity = Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, id, ctx.fixturePos, Vector(0, 0), nil)
        ctx.fixture = { ptr = EntityPtr(entity), hash = GetPtrHash(entity), key = key }
        local pickup = assert(entity:ToPickup(), "origin is not a pickup")
        pickup.Price, pickup.ShopItemId, pickup.AutoUpdatePrice, pickup.OptionsPickupIndex = 0, -1, false, 0
        ctx.sourceVariant, ctx.sourceId = variant, id
    end)
    plan.waitUntil(function(_, ctx)
        local pickup = livePickup(ctx)
        return pickup ~= nil and pickup.FrameCount >= 1, "origin pedestal missing or not initialized"
    end, 60, key .. ": origin pedestal initialized")
    plan.require("REPENTOGON collectible cycle API", function(_, ctx)
        local p = livePickup(ctx)
        local ok = p and type(p.GetCollectibleCycle) == "function" and type(p.AddCollectibleCycle) == "function"
            and type(p.RemoveCollectibleCycle) == "function"
        return ok and true or nil, ok and "EntityPickup cycle methods" or "unavailable without REPENTOGON"
    end)
    plan.act(function(_, ctx)
        local p = assert(livePickup(ctx), "origin pedestal disappeared")
        p:RemoveCollectibleCycle()
        for _, extra in ipairs({ CollectibleType.COLLECTIBLE_SAD_ONION, CollectibleType.COLLECTIBLE_INNER_EYE }) do
            assert(p:AddCollectibleCycle(extra), "AddCollectibleCycle refused " .. extra)
        end
        local source, target = circleOf(p), {}
        for i, id in ipairs(source) do target[i] = id == ctx.sourceId and item.id or id end
        ctx.wheel = { entity = p, hash = GetPtrHash(p), head = p.SubType, ptr = EntityPtr(p), seed = p.InitSeed,
            token = {}, turns = {}, source = source, target = target, post = 0 }
        p:GetData()[CYCLE_PROBE_KEY] = ctx.wheel.token
        morphWatch = { hash = ctx.wheel.hash, post = 0 }
    end)
    plan.waitUntil(function(_, ctx)
        trackTurns(ctx)
        return #ctx.wheel.turns >= 3, #ctx.wheel.turns .. " native turns"
    end, 400, "the pedestal turns by itself")
    plan.note("native turn", function(_, ctx)
        local n = #ctx.wheel.turns
        return string.format("every %s updates; EntityPtr kept %d/%d; GetData kept %d/%d; InitSeed kept %d/%d; MC_POST_PICKUP_MORPH on %d/%d",
            tostring(ctx.wheel.turns[n].gap), turnsWhere(ctx, function(t) return t.ptr end), n,
            turnsWhere(ctx, function(t) return t.data end), n, turnsWhere(ctx, function(t) return t.seed end), n,
            turnsWhere(ctx, function(t) return t.morphs > 0 end), n)
    end)
    plan.check("native turns keep the same circle of choices", function(_, ctx)
        local broken = turnsWhere(ctx, function(t) return not t.committed and not t.circle end)
        return broken == 0, broken .. " of " .. #ctx.wheel.turns .. " turns broke the circle; now "
            .. table.concat(circleOf(ctx.wheel.entity), ",")
    end)
    plan.check("a turn that re-initializes the pickup arrives as a Morph the transaction can follow", function(_, ctx)
        local lost = turnsWhere(ctx, function(t) return (not t.ptr or not t.data) and t.morphs == 0 end)
        return lost == 0, lost == 0 and "every re-initializing turn raised MC_POST_PICKUP_MORPH"
            or lost .. " turns re-initialized the pickup without MC_POST_PICKUP_MORPH"
    end)
    plan.waitUntil(function(_, ctx)
        trackTurns(ctx)
        return ctx.wheel.entity.SubType == ctx.sourceId, "showing " .. tostring(ctx.wheel.entity.SubType)
    end, 400, "Dead Eye shows on the pedestal")
    plan.act(function(player, ctx)
        local p = assert(ctx.wheel.entity:ToPickup(), "fixture is not a pickup")
        local job, reason = ConchBlessing.upgrade.queuePickup(p, key, player)
        assert(job, "queue refused: " .. tostring(reason))
        assert(job.cyclePlan, "queued without its cycle plan")
        ctx.job = job
        ctx.turnsBefore = #ctx.wheel.turns
    end)
    plan.waitUntil(function(_, ctx)
        trackTurns(ctx)
        local job = ctx.job
        return job.status == "complete" or job.status == "cancelled",
            "job=" .. tostring(job.status) .. " committed=" .. tostring(job.committed == true)
    end, 400, key .. ": the upgrade transaction finishes")
    plan.check(key .. ": the upgrade commits while the pedestal turns", function(_, ctx)
        local job = ctx.job
        return job.status == "complete" and job.committed == true,
            "end=" .. tostring(job.endReason) .. " committed=" .. tostring(job.committed == true)
    end)
    plan.check(key .. ": the pedestal turned before the change", function(_, ctx)
        local n = 0
        for i = ctx.turnsBefore + 1, #ctx.wheel.turns do
            if not ctx.wheel.turns[i].committed then n = n + 1 end
        end
        if n == 0 then return nil, "no native turn before the change; inconclusive" end
        return true, n .. " turns before the change"
    end)
    plan.check(key .. ": the pedestal stayed locked through every turn before the change", function(_, ctx)
        local open = 0
        for i = ctx.turnsBefore + 1, #ctx.wheel.turns do
            if ctx.wheel.turns[i].locked == false then open = open + 1 end
        end
        return open == 0, open .. " turns left it collectible"
    end)
    plan.check(key .. ": Dead Eye became Live Eye and every other choice stayed, in the same circle", function(_, ctx)
        local now = circleOf(ctx.wheel.entity)
        return sameCircle(now, ctx.wheel.target),
            "now " .. table.concat(now, ",") .. "; want " .. table.concat(ctx.wheel.target, ",")
    end)
    plan.waitUntil(function(_, ctx)
        trackTurns(ctx)
        return turnsWhere(ctx, function(t) return t.committed end) >= 2, "turns since the change"
    end, 400, key .. ": the converted pedestal keeps turning")
    plan.check(key .. ": the converted pedestal turns through the new circle", function(_, ctx)
        local broken = turnsWhere(ctx, function(t) return t.committed and not t.circle end)
        return broken == 0, broken .. " turns after the change broke the circle; now "
            .. table.concat(circleOf(ctx.wheel.entity), ",")
    end)
    plan.act(function(_, ctx)
        morphWatch = nil
        removeFixture(ctx)
        ctx.wheel = nil
    end)
end

local function build(plan, only)
    plan.section("project sounds", nil)
    plan.check("content/sounds.xml sounds are registered (restart the game after adding them)", function()
        local missing = {}
        for _, name in ipairs(PROJECT_SOUNDS) do
            local id = Isaac.GetSoundIdByName(name)
            if type(id) ~= "number" or id <= 0 then missing[#missing + 1] = name end
        end
        return #missing == 0, #missing == 0 and (#PROJECT_SOUNDS .. " sounds") or "missing: " .. table.concat(missing, ", ")
    end)
    plan.require("real upgrade queue available", function()
        return ConchBlessing.upgrade and type(ConchBlessing.upgrade.queuePickup) == "function", "ConchBlessing.upgrade.queuePickup"
    end)
    for _, row in ipairs(Visuals.catalog) do
        if row.effect and (not only or only == row.key) then stageApplied(plan, row.key) end
    end
    if not only or only == "default" then
        for _, flag in ipairs({ "positive", "neutral", "negative" }) do stageDefault(plan, flag) end
    end
    if not only or only == "cycle" then stageCycle(plan) end
end

local function cleanup(ctx)
    morphWatch = nil
    removeFixture(ctx)
end

TestBench.register({ command = "conch_test morph", tag = "MorphProbe", duration = "about 75 seconds",
    cleanup = cleanup, build = function(plan) build(plan) end })
TestBench.register({ command = "conch_test morph default", tag = "MorphProbe", duration = "about 15 seconds",
    cleanup = cleanup, build = function(plan) build(plan, "default") end })
TestBench.register({ command = "conch_test morph cycle", tag = "MorphProbe", duration = "about 25 seconds",
    cleanup = cleanup, build = function(plan) build(plan, "cycle") end })
for _, row in ipairs(Visuals.catalog) do
    if row.effect then
        TestBench.register({ command = "conch_test morph " .. string.lower(row.key), tag = "MorphProbe",
            duration = "about 10 seconds", cleanup = cleanup, build = function(plan) build(plan, row.key) end })
    end
end

-- Commands for item_probe's dispatcher and conch_test morph list.
function Probe.commandFor(word)
    if not word then return "conch_test morph" end
    if word == "default" then return "conch_test morph default" end
    if word == "cycle" then return "conch_test morph cycle" end
    local key = Visuals.resolveKey(word)
    if key and Visuals.isApplied(key) then return "conch_test morph " .. string.lower(key) end
end
function Probe.list()
    local lines = { "conch_test morph [all applied presentations + default flags + rotating pedestal]",
        "conch_test morph default", "conch_test morph cycle (a rotating pedestal turning during its upgrade)" }
    for _, row in ipairs(Visuals.catalog) do
        if row.effect then lines[#lines + 1] = "conch_test morph " .. string.lower(row.key) .. " (" .. row.effect .. ")" end
    end
    return lines
end

return Probe
