-- Pure bookkeeping for conch_test hemispatial_neglect right_eye. Nothing here
-- touches the engine: the bench feeds it what the engine reported during one
-- burst of real weapon triggers, and the offline tests feed it scripted bursts,
-- so the oracle itself can be run against deliberately wrong items.
--
-- Each tear carries the item's suppression marker and the engine's record of
-- the eye that fired its shot (REPENTOGON TearDisplacement: -1 left, 1 right).
-- A burst's left/right split depends on the native phase it starts in: the
-- 2026-10-23 log shows a six-trigger Eye Drops burst holding 4 left / 2 right
-- tears in one phase and 3 / 3 in the next. Expected counts therefore come
-- from each burst's own eye record, never from "half of the control", and two
-- bursts' timing is compared only when they fired the same eye schedule.
local M = { LEFT = -1, RIGHT = 1 }

function M.new(owner)
    return { owner = owner, tears = {}, triggers = {}, inputGaps = 0, blockedEntities = {} }
end

-- frame: game frame of the post-fire event; blocked: the item's marker;
-- eye: the engine's eye record for the shot (nil when unavailable).
function M.addTear(s, frame, blocked, eye)
    s.tears[#s.tears + 1] = { frame = frame, blocked = blocked == true, eye = eye }
end

function M.addTrigger(s, frame)
    s.triggers[#s.triggers + 1] = frame
end

local function letter(eye)
    if eye == M.LEFT then return "L" elseif eye == M.RIGHT then return "R" end
    return "?"
end

-- eyes: one letter per tear in firing order; marks: the same letters with
-- suppressed tears in lower case; offsets: trigger frames from the first one.
function M.summarize(s, survivors)
    local r = { total = #s.tears, kept = 0, blocked = 0, left = 0, right = 0, unknown = 0,
        leftBlocked = 0, rightKept = 0, offsets = {}, inputGaps = s.inputGaps or 0,
        survivors = survivors or 0 }
    local eyes, marks = {}, {}
    for i, tear in ipairs(s.tears) do
        local l = letter(tear.eye)
        eyes[i], marks[i] = l, tear.blocked and l:lower() or l
        if tear.blocked then r.blocked = r.blocked + 1 else r.kept = r.kept + 1 end
        if l == "L" then
            r.left = r.left + 1
            if tear.blocked then r.leftBlocked = r.leftBlocked + 1 end
        elseif l == "R" then
            r.right = r.right + 1
            if not tear.blocked then r.rightKept = r.rightKept + 1 end
        else
            r.unknown = r.unknown + 1
        end
    end
    r.eyes, r.marks = table.concat(eyes), table.concat(marks)
    for i, frame in ipairs(s.triggers) do r.offsets[i] = frame - s.triggers[1] end
    return r
end

function M.describe(r)
    return string.format("eyes=%s marks=%s trigger offsets=%s inputGaps=%d remaining=%d",
        r.eyes ~= "" and r.eyes or "-", r.marks ~= "" and r.marks or "-",
        #r.offsets > 0 and table.concat(r.offsets, ",") or "-", r.inputGaps, r.survivors)
end

-- Same native phase: the engine fired the same eyes in the same order over the
-- same number of triggers.
function M.samePhase(a, b)
    return a.eyes == b.eyes and #a.offsets == #b.offsets
end

-- Largest per-trigger timing difference; nil when the trigger counts differ.
function M.timingDifference(a, b)
    if #a.offsets ~= #b.offsets then return nil end
    local worst = 0
    for i = 1, #a.offsets do worst = math.max(worst, math.abs(a.offsets[i] - b.offsets[i])) end
    return worst
end

function M.agrees(a, b, tolerance)
    local diff = M.timingDifference(a, b)
    return M.samePhase(a, b) and diff ~= nil and diff <= tolerance
end

-- The vanilla reference is a schedule two control bursts reproduced; an
-- interrupted or differently phased control burst never becomes the oracle.
function M.reference(attempts, tolerance)
    for i = 2, #attempts do
        for j = 1, i - 1 do
            if M.agrees(attempts[i], attempts[j], tolerance) then return attempts[j] end
        end
    end
end

-- The item burst to compare with the control is the first one that fired the
-- control's eye schedule with its shooting input delivered on every update.
-- Timing is never a selection criterion, so a cadence change cannot be
-- resampled away. A same-phase burst with an input gap is used only once no
-- attempt is left (final), so a false gap report alone cannot fail the bench.
function M.comparable(attempts, ref, final)
    local fallback
    for _, r in ipairs(attempts) do
        if M.samePhase(r, ref) then
            if r.inputGaps == 0 then return r end
            fallback = fallback or r
        end
    end
    if final then return fallback end
end

-- The item's eye contract on one burst, judged by that burst's own evidence.
-- eyesPerShot is the engine's count of eyes firing each shot: with one, the
-- shot's eye record covers all of its tears; with two (The Wiz) the record
-- cannot tell the pair apart, so exactly one tear of each pair is suppressed.
function M.eyeContract(r, owned, eyesPerShot)
    if r.total == 0 then return false, "no tear observed" end
    if r.survivors > 0 then return false, r.survivors .. " suppressed tear(s) still exist" end
    if not owned then
        return r.blocked == 0, string.format("blocked=%d of %d", r.blocked, r.total)
    end
    if eyesPerShot == 2 then
        return r.blocked * 2 == r.total,
            string.format("both-eye shots: blocked=%d kept=%d of %d", r.blocked, r.kept, r.total)
    end
    if eyesPerShot ~= 1 then return nil, "unsupported eyes per shot: " .. tostring(eyesPerShot) end
    if r.unknown > 0 then return false, r.unknown .. " tear(s) without an engine eye record" end
    if r.left == 0 or r.right == 0 then
        return false, string.format("burst lacks a shot from each eye (left=%d right=%d)", r.left, r.right)
    end
    return r.leftBlocked == 0 and r.rightKept == 0,
        string.format("left kept=%d blocked=%d; right kept=%d blocked=%d",
            r.left - r.leftBlocked, r.leftBlocked, r.rightKept, r.right - r.rightKept)
end

-- A control burst is an oracle only if nothing was suppressed and, for
-- one-eye shots, every tear has an eye record and both eyes fired.
function M.controlContract(r, eyesPerShot)
    local ok, detail = M.eyeContract(r, false, eyesPerShot)
    if not ok then return ok, detail end
    if eyesPerShot == 1 then
        if r.unknown > 0 then return false, r.unknown .. " tear(s) without an engine eye record" end
        if r.left == 0 or r.right == 0 then
            return false, string.format("burst lacks a shot from each eye (left=%d right=%d)", r.left, r.right)
        end
    elseif eyesPerShot ~= 2 then
        return nil, "unsupported eyes per shot: " .. tostring(eyesPerShot)
    end
    return true, detail
end

function M.expected(ref, owned, eyesPerShot)
    local blocked = 0
    if owned then blocked = eyesPerShot == 2 and ref.total / 2 or ref.right end
    return ref.total - blocked, blocked
end

-- A same-phase item burst must keep exactly the control's left-eye output,
-- drop exactly its right-eye output and fire on the control's frames.
function M.matchesControl(r, ref, owned, eyesPerShot, tolerance)
    local kept, blocked = M.expected(ref, owned, eyesPerShot)
    local diff = M.timingDifference(r, ref)
    local ok = r.total == ref.total and r.kept == kept and r.blocked == blocked
        and diff ~= nil and diff <= tolerance
    return ok, string.format(
        "kept expected=%s actual=%d; blocked expected=%s actual=%d; trigger offsets control=%s actual=%s (largest difference %s, tolerance %d)",
        tostring(kept), r.kept, tostring(blocked), r.blocked, table.concat(ref.offsets, ","),
        table.concat(r.offsets, ","), tostring(diff), tolerance)
end

return M
