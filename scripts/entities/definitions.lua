-- Pure data shared by generate_xml.py and the owning runtime subsystem.
-- Omit variant so the engine allocates a non-colliding custom variant.
return {
    NEGLECT_TEAR = {
        name = "Conch Blessing Suppressed Tear", id = 2,
        anm2path = "002.000_Tear.anm2",
        collisionDamage = 0, collisionMass = 8, collisionRadius = 0,
        friction = 1, numGridCollisionPoints = 0, shadowSize = 0,
    },
}
