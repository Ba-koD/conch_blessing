-- Pure data shared by generate_xml.py and the owning runtime subsystem.
-- Omit variant so the engine allocates a non-colliding custom variant. Effects
-- (id 1000) are the exception: without one the engine leaves them at variant 0
-- (measured 2026-10-31), so an effect names its own.
return {
    NEGLECT_TEAR = {
        name = "Conch Blessing Suppressed Tear", id = 2,
        anm2path = "002.000_Tear.anm2",
        collisionDamage = 0, collisionMass = 8, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
    -- 축's two oxen: subtype 0 누렁소, 1 검은소. They only walk and draw. No
    -- installed mod used effect variants 7700-7900 on 2026-10-31.
    OX = {
        name = "Conch Blessing Ox", id = 1000, variant = 7783,
        anm2path = "effects/conch_ox.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 22,
    },
    -- One cell of an ox's furrow, drawn on the floor (subtype 0 누렁소, 1 검은소).
    OX_FURROW = {
        name = "Conch Blessing Ox Furrow", id = 1000, variant = 7784,
        anm2path = "effects/conch_ox_furrow.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
    -- Rice growing where the yellow ox's furrow meets the black ox's ditch.
    OX_RICE = {
        name = "Conch Blessing Ox Rice", id = 1000, variant = 7785,
        anm2path = "effects/conch_ox_rice.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
}
