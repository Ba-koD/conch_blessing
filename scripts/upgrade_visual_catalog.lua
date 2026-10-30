-- Order is shared by the console viewer and the standalone HTML preview.
-- A pending concept retains the existing flag-based animation in game.
return {
    { key = "LIVE_EYE" },
    { key = "VOID_DAGGER", effect = "void", impact = 51 },
    { key = "ETERNAL_FLAME" },
    { key = "POWER_TRAINING" },
    { key = "ORAL_STEROIDS" },
    { key = "INJECTABLE_STEROIDS" },
    { key = "DRAGON", effect = "lightning", impact = 70, duration = 127, nativeResult = true },
    { key = "KRONOS", effect = "saturn", impact = 120, duration = 170 },
    { key = "APPRAISAL_CERTIFICATE" },
    { key = "MONEY_TEAR", effect = "rain", impact = 96, duration = 174 },
    { key = "UTILITY_BELT" },
    { key = "SEALED_DEMON_SWORD" },
    { key = "TYRFING" },
    { key = "ICE_BREATH", effect = "ice", impact = 45 },
    { key = "FIRE_BREATH", effect = "fire", impact = 45 },
    { key = "SOFLAM", effect = "missile", impact = 53 },
    { key = "TWO_FACED_PENNY" },
    { key = "SEVERED_OATH" },
    { key = "CEIL" },
    { key = "ROUND" },
    { key = "FLOOR" },
    { key = "REAL_EYES" },
    { key = "AR_GLASSES" },
    -- The left half of the view fades to black, the item changes in it, and it returns.
    { key = "HEMISPATIAL_NEGLECT", effect = "neglect", impact = 66, duration = 126 },
    -- Every time item shares one clock presentation (6:00 to 12:00, 째깍, 댕).
    { key = "TIME_MONEY", effect = "clock", impact = 96, duration = 150 },
    { key = "TIME_POWER", effect = "clock", impact = 96, duration = 150 },
    { key = "TIME_TEAR", effect = "clock", impact = 96, duration = 150 },
    { key = "TIME_LUCK", effect = "clock", impact = 96, duration = 150 },
    { key = "F_MINUS" },
    { key = "C_MINUS" },
    { key = "B_MINUS" },
    { key = "A_MINUS" },
    { key = "ATROPOS" },
    -- Both crowns have visible bounds (4,10)-(29,28) in their 32px art.
    -- Effects follow the crown's silhouette centre, not transparent padding.
    { key = "ANGELS_CROWN", effect = "purify", impact = 41, anchorX = 16.5, anchorY = 19 },
    -- Every Magic Conch result has a row, so the preview can show its default too.
    { key = "RAT" },
    { key = "CONCH_PEARL" },
}
