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
    -- 장승's statues. They only stand and draw.
    JANGSEUNG = {
        name = "Conch Blessing Jangseung", id = 1000, variant = 7786,
        anm2path = "effects/conch_jangseung.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 12,
    },
    -- The trodden earth in front of a pair, drawn into the floor.
    JANGSEUNG_GROUND = {
        name = "Conch Blessing Jangseung Ground", id = 1000, variant = 7787,
        anm2path = "effects/conch_jangseung_ground.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
    -- 묘's rabbit tracks leading into its hidden rock, drawn into the floor.
    RABBIT_TRACKS = {
        name = "Conch Blessing Rabbit Tracks", id = 1000, variant = 7788,
        anm2path = "effects/conch_rabbit_tracks.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
    -- 전우치 arriving where a stolen item will stand, casting and vanishing
    -- in smoke; its frames draw their own shadow.
    JEON_WOOCHI = {
        name = "Conch Blessing Jeon Woo-chi", id = 1000, variant = 7789,
        anm2path = "effects/conch_jeonwoochi.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
    -- 지뢰's mine lying on the floor where a missed tear fell; the module
    -- finds what steps on it and deals its blast itself.
    LANDMINE = {
        name = "Conch Blessing Landmine", id = 1000, variant = 7790,
        anm2path = "effects/conch_landmine.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
    -- The 금줄 strung between a 장승 pair (subtype: its tag's icon number * 2,
    -- plus 1 for a red rope). It only hangs and draws.
    JANGSEUNG_ROPE = {
        name = "Conch Blessing Jangseung Rope", id = 1000, variant = 7791,
        anm2path = "effects/conch_jangseung_rope.anm2",
        collisionDamage = 0, collisionMass = 0, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
}
