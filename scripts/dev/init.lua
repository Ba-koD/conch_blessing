local require = ConchBlessingRequire or require -- reloadable loader, see main.lua
-- Dev tooling entry point. The Workshop package leaves scripts/dev out, and
-- core loads this file last through ConchBlessingOptionalRequire, so nothing in
-- the released mod registers a bench, a probe or a dev callback. Production
-- code never requires scripts.dev.* itself.
local function load(name)
    local ok, err = pcall(require, "scripts.dev." .. name)
    if not ok then ConchBlessing.printError("[Dev] " .. name .. " load failed: " .. tostring(err)) end
end

load("runtime_queue")      -- __CBQ__ command queue (watch.sh, queued benches)
load("morph_viewer")       -- conch_morph: previews an upgrade presentation
load("rng_probe")          -- conch_test rng
load("stat_rounding_probe") -- conch_test rounding
load("kronos_probe")       -- conch_test kronos detail
load("liveeye_probe")      -- conch_test live_eye detail
for _, probe in ipairs({ "thurisaz_probe", "conch_ticket_probe", "uruz_probe" }) do load(probe) end
load("locale_probe")       -- conch_test locale
load("morph_probe")        -- conch_test morph
load("evolution_probe")    -- conch_test evolution
load("appraisal_probe")    -- conch_test appraisal detail
-- Last, so conch_test can include the detailed benches above in its suite.
load("item_probe")

return {}
