-- Independent observables/oracles for the native Soul of Isaac / Oath benches.
-- Never reads Oath's ledger, calls its callbacks, or draws from an item pool.
local M = {}

function M.canonical(ring)
    assert(#ring > 0 and #ring <= 9, "invalid cycle length")
    local best
    for first = 1, #ring do
        local row = {}
        for offset = 0, #ring - 1 do
            local id = ring[(first + offset - 1) % #ring + 1]
            assert(type(id) == "number" and id > 0 and id % 1 == 0, "invalid cycle ID")
            row[#row + 1] = tostring(id)
        end
        local value = table.concat(row, ",")
        if not best or value < best then best = value end
    end
    return best
end

function M.metadata(row)
    return table.concat({tostring(row.price), tostring(row.options), tostring(row.shop), tostring(row.auto)}, ":")
end

function M.signature(rows, identity, includeMetadata)
    local result = {}
    for _, row in ipairs(rows) do
        local key = identity == "anchor" and row.anchor .. ":" .. row.seed or identity and row.key
        result[#result + 1] = (key and key .. "=" or "") .. M.canonical(row.ring)
            .. (includeMetadata == false and "" or "@" .. M.metadata(row))
    end
    table.sort(result)
    return table.concat(result, "|")
end

function M.total(rows)
    local n = 0
    for _, row in ipairs(rows) do n = n + #row.ring end
    return n
end

function M.copyRows(rows)
    local result = {}
    for _, row in ipairs(rows) do
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        copy.ring = {}; for i, id in ipairs(row.ring) do copy.ring[i] = id end
        result[#result + 1] = copy
    end
    return result
end

local function counts(ring)
    local result = {}
    for _, id in ipairs(ring) do result[id] = (result[id] or 0) + 1 end
    return result
end

-- Audit only new occurrences. Existing duplicates and deliberate native copies
-- are not rewritten or retroactively labelled a broken bonus.
function M.auditGrant(window, expectedPool)
    local audit = {same = 0, cross = 0, existing = 0, added = {}, collisions = {}, source = true}
    local beforeByAnchor, oldRooms, newRooms = {}, {}, {}
    for _, row in ipairs(window.before) do
        beforeByAnchor[row.anchor] = counts(row.ring)
        for id, n in pairs(beforeByAnchor[row.anchor]) do
            audit.existing = audit.existing + math.max(0, n - 1)
            oldRooms[id] = oldRooms[id] or {}; oldRooms[id][row.anchor] = true
        end
    end
    for _, row in ipairs(window.after) do
        local old = beforeByAnchor[row.anchor]
        if not old then audit.source = nil; audit.sourceDetail = "pedestal identity changed"; return audit end
        for id, n in pairs(counts(row.ring)) do
            local added = n - (old[id] or 0)
            if added > 0 then
                local collision = (old[id] or 0) > 0 and added or math.max(0, added - 1)
                audit.same = audit.same + collision
                if collision > 0 then audit.collisions[#audit.collisions + 1] = "same:" .. id .. "@" .. row.anchor end
                newRooms[id] = newRooms[id] or {}; newRooms[id][row.anchor] = true
                for _ = 1, added do audit.added[#audit.added + 1] = {id = id, anchor = row.anchor} end
            end
        end
    end
    for _, choice in ipairs(audit.added) do
        local cross = false
        for anchor in pairs(oldRooms[choice.id] or {}) do if anchor ~= choice.anchor then cross = true end end
        for anchor in pairs(newRooms[choice.id] or {}) do if anchor ~= choice.anchor then cross = true end end
        if cross then
            audit.cross = audit.cross + 1
            audit.collisions[#audit.collisions + 1] = "cross:" .. choice.id .. "@" .. choice.anchor
        end
    end
    local pool = window.poolBefore
    local members, available = {}, 0
    if pool and type(expectedPool) == "number" then
        for _, entry in pairs(pool.entries) do
            if entry.pool == expectedPool then
                members[entry.id] = true
                if entry.weight > entry.threshold and entry.unlocked == true and not (pool.removed or {})[entry.id] then
                    available = available + 1
                end
            end
        end
    end
    local details, unknown = {}, false
    for _, choice in ipairs(audit.added) do
        local matched, wrong
        for _, event in ipairs(window.events) do
            if event.decrease and event.id == choice.id then
                if event.requested == expectedPool and event.actual == expectedPool then matched = true
                elseif type(event.actual) == "number" and type(event.requested) == "number" then
                    wrong = "requested=" .. event.requested .. ",actual=" .. event.actual
                end
            end
        end
        if not pool or available == 0 or not window.callbackKnown then
            unknown = true; details[#details + 1] = choice.id .. ":unknown_or_depleted_pool"
        elseif not matched and wrong then
            audit.source = false; details[#details + 1] = choice.id .. ":wrong_pool(" .. wrong .. ")"
        elseif not members[choice.id] or not matched then
            unknown = true; details[#details + 1] = choice.id .. ":unresolved_final_ID_or_provider_override"
        else details[#details + 1] = choice.id .. ":room_pool_match" end
    end
    if audit.source ~= false and unknown then audit.source = nil end
    table.sort(details); table.sort(audit.collisions)
    audit.sourceDetail = "expectedPool=" .. tostring(expectedPool) .. "; " .. table.concat(details, ",")
    -- A new overlap is visible and unresolved, not automatically a gameplay bug:
    -- native/provider-selected repeats and pool exhaustion need runtime evidence.
    audit.overlap = audit.same == 0 and audit.cross == 0 and true or nil
    audit.overlapDetail = "existingDuplicateOccurrences=" .. audit.existing .. "; newSame=" .. audit.same
        .. "; newCross=" .. audit.cross .. "; " .. table.concat(audit.collisions, ",")
    return audit
end

-- Removing only the added occurrences must recover the old circular sequence.
-- Sorting or set comparison would hide lost duplicates and reordered choices.
function M.cycleAddition(before, after, extra)
    local a, b = before.ring, after.ring
    local wanted = math.min(9, #a + extra)
    if #b ~= wanted then return false, "choices=" .. #b .. " expected=" .. wanted end
    for start = 1, #b do
        local matched = 0
        for offset = 0, #b - 1 do
            if b[(start + offset - 1) % #b + 1] == a[matched + 1] then matched = matched + 1 end
            if matched == #a then return true, "old circular order and every occurrence retained" end
        end
    end
    return false, "old sequence=" .. M.canonical(a) .. " actual=" .. M.canonical(b)
end

function M.addition(before, after, extra)
    if M.metadata(before) ~= M.metadata(after) then return false, "price/options/shop/auto changed" end
    return M.cycleAddition(before, after, extra)
end

local function matchRows(before, after, validate)
    if #before ~= #after then return false, "pedestals=" .. #after .. " expected=" .. #before end
    local used = {}
    -- Fixtures have stable distinct positions; native room reloads replace pointers.
    for _, old in ipairs(before) do
        local found
        for i, new in ipairs(after) do
            if not used[i] and new.anchor == old.anchor then
                used[i], found = true, true
                local ok, detail = validate(old, new)
                if not ok then return false, old.anchor .. ": " .. detail end
                break
            end
        end
        if not found then return false, "missing pedestal at " .. old.anchor end
    end
    return true
end

function M.additions(before, after, extra)
    local ok, detail = matchRows(before, after, function(a, b) return M.addition(a, b, extra) end)
    return ok, detail or "occurrences/order/metadata preserved"
end

function M.cycleAdditions(before, after, extra)
    local ok, detail = matchRows(before, after, function(a, b) return M.cycleAddition(a, b, extra) end)
    return ok, detail or "occurrences/order preserved"
end

-- Metadata is still a strict assertion, but its failure must not conceal the
-- independent cycle/cost result or abort copy/rewrite tests with a valid cycle.
function M.sameMetadata(before, after)
    local ok, detail = matchRows(before, after, function(a, b)
        local old, new = M.metadata(a), M.metadata(b)
        return old == new, "price/options/shop/auto before=" .. old .. " after=" .. new
    end)
    return ok, detail or "price/options/shop/auto preserved"
end

function M.stock()
    local rows = {}
    -- FindByType omits FLAG_NO_QUERY. An observer must not mistake a live
    -- pedestal hidden from that query for a removed cycle or empty fixture.
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == EntityType.ENTITY_PICKUP and entity.Variant == PickupVariant.PICKUP_COLLECTIBLE
            and entity:Exists() then
            local p = entity:ToPickup()
            if p and p.SubType > 0 then rows[#rows + 1] = p end
        end
    end
    return rows
end

function M.describeEntity(entity, duringRemoval)
    if not entity or not duringRemoval and not entity:Exists() then return "removed" end
    local hidden = EntityFlag and EntityFlag.FLAG_NO_QUERY and entity:HasEntityFlags(EntityFlag.FLAG_NO_QUERY)
    local position = entity.Position
    local sprite = type(entity.GetSprite) == "function" and entity:GetSprite()
    -- ENTITY_REMOVE supplies the base Entity, not necessarily EntityPickup.
    local pickup = type(entity.ToPickup) == "function" and entity:ToPickup()
    return string.format("%s.%s.%s:seed=%s:age=%s:noQuery=%s:exists=%s:timeout=%s:state=%s:pos=%s,%s:anim=%s",
        tostring(entity.Type), tostring(entity.Variant), tostring(entity.SubType), tostring(entity.InitSeed),
        tostring(entity.FrameCount), tostring(hidden), tostring(entity:Exists()), tostring(pickup and pickup.Timeout),
        tostring(pickup and pickup.State), tostring(position and position.X), tostring(position and position.Y),
        tostring(sprite and sprite:GetAnimation()))
end

function M.snapshot()
    local result = {}
    for _, p in ipairs(M.stock()) do
        local ring = {p.SubType}
        for _, id in ipairs(p:GetCollectibleCycle()) do ring[#ring + 1] = id end
        M.canonical(ring)
        for _, id in ipairs(ring) do assert(Isaac.GetItemConfig():GetCollectible(id), "missing item config " .. id) end
        result[#result + 1] = {ring = ring, key = tostring(GetPtrHash(p)) .. ":" .. p.InitSeed,
            seed = p.InitSeed, anchor = string.format("%.0f,%.0f", p.Position.X, p.Position.Y),
            price = p.Price, options = p.OptionsPickupIndex, shop = p.ShopItemId, auto = p.AutoUpdatePrice}
    end
    return result
end

local function readSet(pool, method)
    if type(pool[method]) ~= "function" then return nil end
    local ok, values = pcall(pool[method], pool)
    if not ok or type(values) ~= "table" then return nil end
    local result = {}
    for key, value in pairs(values) do
        -- REPENTOGON returns a dense ID -> boolean map, including false entries.
        local id = type(value) == "boolean" and tonumber(key) or type(value) == "number" and value or nil
        if not id or id <= 0 or id % 1 ~= 0 then return nil end
        if value ~= false then result[id] = true end
    end
    return result
end

function M.poolSnapshot()
    local pool, result = Game():GetItemPool(), {entries = {}}
    if type(pool.GetNumItemPools) ~= "function" or type(pool.GetCollectiblesFromPool) ~= "function" then return nil end
    local count = pool:GetNumItemPools()
    assert(type(count) == "number" and count > 0 and count % 1 == 0, "invalid native pool count")
    for kind = 0, count - 1 do
        local entries = pool:GetCollectiblesFromPool(kind)
        assert(type(entries) == "table", "incompatible native pool snapshot")
        local occurrences = {}
        for _, entry in ipairs(entries) do
            assert(type(entry.itemID) == "number" and type(entry.weight) == "number"
                and type(entry.removeOn) == "number", "incompatible PoolItem schema")
            occurrences[entry.itemID] = (occurrences[entry.itemID] or 0) + 1
            result.entries[kind .. ":" .. entry.itemID .. ":" .. occurrences[entry.itemID]] = {
                pool = kind, id = entry.itemID,
                weight = entry.weight, threshold = entry.removeOn, unlocked = entry.isUnlocked,
                decrease = entry.decreaseBy, initial = entry.initialWeight}
        end
    end
    result.removed = readSet(pool, "GetRemovedCollectibles")
    result.blacklist = readSet(pool, "GetRoomBlacklistedCollectibles")
    return result
end

function M.poolDelta(before, after)
    if not before or not after then return {known = false, lost = 0, changed = 0, removed = 0, blocked = 0, detail = "pool_snapshot=unknown"} end
    local delta = {known = before.removed ~= nil and after.removed ~= nil
        and before.blacklist ~= nil and after.blacklist ~= nil, lost = 0, changed = 0, removed = 0, blocked = 0}
    local keys, details = {}, {}
    for key in pairs(before.entries) do keys[key] = true end
    for key in pairs(after.entries) do keys[key] = true end
    for key in pairs(keys) do
        local a, b = before.entries[key], after.entries[key]
        if not a or not b then
            delta.changed = delta.changed + 1
            delta.lost = delta.lost + (a and a.weight or 0) -- added weights never cancel a loss
            details[#details + 1] = key .. ":entry_changed"
        elseif a.weight ~= b.weight or a.threshold ~= b.threshold or a.unlocked ~= b.unlocked
            or a.decrease ~= b.decrease or a.initial ~= b.initial then
            delta.changed = delta.changed + 1
            delta.lost = delta.lost + math.max(0, a.weight - b.weight)
            details[#details + 1] = key .. ":" .. a.weight .. ">" .. b.weight
        end
    end
    for id in pairs(after.removed or {}) do
        if not (before.removed or {})[id] then delta.removed = delta.removed + 1; details[#details + 1] = "removed:" .. id end
    end
    for id in pairs(after.blacklist or {}) do
        if not (before.blacklist or {})[id] then delta.blocked = delta.blocked + 1; details[#details + 1] = "blacklist:" .. id end
    end
    table.sort(details)
    delta.detail = #details > 0 and table.concat(details, ",") or "none"
    return delta
end

function M.drawCounts(events)
    local decrease, preview = 0, 0
    for _, event in ipairs(events) do
        if event.decrease then decrease = decrease + 1 else preview = preview + 1 end
    end
    return decrease, preview
end

function M.noCharge(window)
    local n = M.drawCounts(window.events)
    local delta = M.poolDelta(window.poolBefore, window.poolAfter)
    if n > 0 or delta.lost > 0 or delta.removed > 0 or delta.blocked > 0 then
        return false, "decreasing callbacks=" .. n .. "; weight lost=" .. delta.lost .. "; removed=" .. delta.removed .. "; blacklisted=" .. delta.blocked
    end
    if not window.callbackKnown or not delta.known then return nil, "pool evidence incomplete; zero is not proven" end
    return true, "no decreasing callbacks, weight loss or new global/room exclusions (all observed providers)"
end

return M
