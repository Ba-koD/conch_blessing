-- Conch Blessing's pocket items (cards and runes). Data only: generate_xml.py
-- reads this file without running Lua to write content/pocketitems.xml, each
-- card's floor pickup row in content/entities2.xml and the pocket-slot art in
-- content/gfx/ui_cardfronts.anm2. scripts/conch_blessing_pockets.lua builds
-- ConchBlessing.PocketData from it at runtime. The English name (the
-- pocketitems.xml name that Isaac.GetCardIdByName looks up) and the other text
-- live under pockets.<KEY> in scripts/locale/<lang>.lua.
--
-- Fields:
--   type         the pocketitems.xml type: "rune", or a card type ("tarot",
--                "tarot_reverse", "suit", "special", "object")
--   pickup       card pickup subtype: the entities2.xml row (id 5, variant 300)
--                that gives the card its own floor sprite; unique across mods
--   hud          animation name in content/gfx/ui_cardfronts.anm2 (pocket slot)
--   anm2         floor pickup animation, relative to resources/gfx
--   gfx          its spritesheet, relative to resources/gfx: body at x=0, glow at
--                x=32, pocket-slot art at x=64, each 32x32 (generate_pocket_assets.py)
--   mimiccharge  charge Blank Card / Clear Rune need to copy it
--   script       behavior module, required once at load
return {
    THURISAZ = {
        type = "rune",
        pickup = 7781,
        hud = "Thurisaz",
        anm2 = "005.300_thurisaz.anm2",
        gfx = "items/pick ups/pickup_thurisaz.png",
        mimiccharge = 6,
        script = "scripts.items.cards.thurisaz",
    },
    CONCH_TICKET = {
        type = "special",
        pickup = 7782,
        hud = "Conch Ticket",
        anm2 = "005.300_conch_ticket.anm2",
        gfx = "items/pick ups/pickup_conch_ticket.png",
        mimiccharge = 4,
        script = "scripts.items.cards.conch_ticket",
    },
}
