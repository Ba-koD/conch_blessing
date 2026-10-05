-- English text for Conch's Blessing, and the fallback for every other language.
-- Pure data: strings, numbers and tables only (tools read this file without Lua).
--
-- items.<KEY> matches ConchBlessing.ItemData.<KEY> in scripts/conch_blessing_items.lua:
--   name, description   pickup title and subtitle
--   eid                 EID description lines; a line starting with # starts a new line
--   synergies.<line>    the line a synergy entry in ItemData points to by name
--   specials            language-specific golden/Mom's Box text (see the specials notes
--                       at the top of conch_blessing_items.lua)
-- Item text is shown as written. Icons: {c:SAD_ONION} vanilla collectible, {t:NAME}
-- vanilla trinket, {card:NAME} card, {own:KEY} this mod's item; a token is the icon
-- alone, so write the space after it. %TOKEN% in a synergy line is a live EID value.
--
-- ui.* strings are string.format templates for code: %s takes an argument and a
-- literal percent sign is written %%. ui.mcm is English-only: Mod Config Menu reads
-- it in English because its fonts are not known to cover every language.
--
-- Run `python check_locale.py` after editing any locale file.
return {
    items = {
        -- Collectibles
        LIVE_EYE = {
            name = "Live Eye",
            description = "Misses happen",
            eid = {
                "{{Damage}} Damage multiplier increases by 0.1 as you hit enemies.",
                "#{{Damage}} Damage multiplier decreases by 0.15 as you miss enemies.",
                "#{{Luck}} 50% chance not to decrease. (5% per luck)",
                "#{{Damage}} Damage multiplier is capped at 3.0 and cannot go below 0.75.",
                "#With a non-tear attack, the {{Damage}}damage multiplier is fixed at x1.5.",
            },
            synergies = {
                rock_bottom = "The damage multiplier is fixed at the maximum, x3.0 (also with a non-tear attack).",
            },
        },
        VOID_DAGGER = {
            name = "Void Dagger",
            description = "The void opens",
            eid = {
                "#When your attack damages an enemy, has a chance to spawn a void ring at the impact that deals your damage",
                "#Chance is (30 − {{Tears}}Tears)% guaranteed 5%",
                "#chance is increased by (1+0.1×{{Luck}}Luck) (up to 100%)",
                "#Duration increases by 10 frames per 10 {{Damage}}Damage by 5 steps",
                "#{{BlackHeart}}No black heart drops",
                "#{{Warning}} REPENTOGON recommended",
            },
        },
        ETERNAL_FLAME = {
            name = "Eternal Flame",
            description = "Baptize with fire",
            eid = {
                "Removes curses when they are applied.",
                "#Grants fixed damage +3.0 and fixed fire rate +1.0 permanently when removing curses.",
                "#Gains 1 {{EternalHeart}} eternal heart.",
            },
        },
        POWER_TRAINING = {
            name = "Power Training",
            description = "Lightweight Baby!",
            eid = {
                "Damage, tears, range, and luck are changed to 1.0~1.3x when used",
                "#Starts with half-charged gauge",
                "#When stacked, increases by addition",
                "#The final multiplier never drops below 0.5",
            },
        },
        ORAL_STEROIDS = {
            name = "Oral Steroids",
            description = "Shots are scary",
            eid = {
                "Damage, fire rate, range, and luck are changed to 0.8 ~ 1.5x when obtained",
                "#When stacked, increases by addition",
                "#The final multiplier never drops below 0.4",
            },
        },
        INJECTABLE_STEROIDS = {
            name = "Injectable Steroids",
            description = "I need more power...",
            eid = {
                "Damage, fire rate, range, and luck are changed to 0.5~2.0x when used",
                "#Starts with half-charged gauge",
                "#When stacked, increases by addition",
                "#The final multiplier never drops below 0.25",
                "#{{Warning}}Your body is gradually turning yellow...",
                "#{{Warning}}Base 1% chance of instant death when used",
                "#{{Warning}}Instant death ignores shields and invincibility; extra lives still activate",
                "#{{Warning}}Death chance increases by 3% each use, resets each floor.",
                "#Each room clear decreases death chance by 0.25%.",
            },
        },
        RAT = {
            name = "Rat",
            description = "Rat",
        },
        OX = {
            name = "Ox",
            description = "Ox",
        },
        TIGER = {
            name = "Tiger",
            description = "Tiger",
        },
        RABBIT = {
            name = "Rabbit",
            description = "Rabbit",
        },
        DRAGON = {
            name = "Dragon",
            description = "God of Weather",
            eid = {
                "Gain flight and Spectral tears.",
                "#Every 5th attack, fires 5 lightning shots in random directions.",
                "#{{Warning}} Requires REPENTOGON!",
            },
            synergies = {
                dragon = {
                    "Lightning shots are replaced with a tornado",
                    "#When the tornado ends, it creates a vortex that pulls in enemies for 2 seconds",
                    "#When the vortex disappears, it explodes for 25x your damage",
                    "#Each additional Dragon increases damage by 25%",
                },
            },
        },
        SNAKE = {
            name = "Snake",
            description = "Snake",
        },
        HORSE = {
            name = "Horse",
            description = "Horse",
        },
        GOAT = {
            name = "Goat",
            description = "Goat",
        },
        MONKEY = {
            name = "Monkey",
        },
        CHICKEN = {
            name = "Chicken",
            description = "Chicken",
        },
        DOG = {
            name = "Dog",
            description = "Dog",
        },
        PIG = {
            name = "Pig",
            description = "Pig",
        },
        KRONOS = {
            name = "Kronos",
            description = "Devours its offspring",
            eid = {
                "Absorbs familiars to gain their unique abilities and 2 damage.",
                "#Some familiars cannot be absorbed according to the exclusion list.",
                "#Current projectile ignore chance: %KRONOS_BLOCK%",
            },
            synergies = {
                twisted_pair = "Adds 2 additional 37.5% damage attacks.",
                succubus = "Attracts an aura around the player.",
                incubus = "Adds 1 additional 75% damage attack.",
                seraphim = {
                    "Gains flight, and spectral tear effects.",
                    "Gains a {c:SACRED_HEART} Sacred Heart (first time only).",
                },
                robo_baby = "Gains {c:TECHNOLOGY} Technology.",
                robo_baby_2 = "Gains {c:TECHNOLOGY_2} Technology 2.",
                blue_babys_only_friend = "Gains {c:LUDOVICO_TECHNIQUE} Ludovico Technique (first time only).",
                lil_brimstone = "Gains {c:BRIMSTONE} Brimstone.",
                bobs_brain = "Gains {c:IPECAC} Ipecac (first time only).",
                lil_monstro = "Gains {c:MONSTROS_LUNG} Monstro's Lung (first time only).",
                lil_haunt = "Grants fear effect to all attacks.",
                blood_puppy = "Gains {c:GIMPY} Gimpy (first time only).",
                angelic_prism = "Attacks split into 4 beams.",
                bot_fly = "Gains {c:LOST_CONTACT} Lost Contact (first time only).",
                freezer_baby = "Gains {c:URANUS} Uranus (first time only).",
                lil_abaddon = "Gains {c:MAW_OF_THE_VOID} Maw of the Void (first time only).",
                multidimensional_baby = "Gains {c:20_20} 20/20.",
                harlequin_baby = "Gains {c:THE_WIZ} The Wiz.",
                brother_bobby = "Gains +2 {{Tears}} fire rate.",
                demon_baby = "Gains {c:MARKED} Marked (first time only).",
                little_gish = "Grants slowing effect to all attacks.",
                lil_loki = "Gains {c:LOKIS_HORNS} Loki's Horns.",
                ghost_baby = "Gains {c:CONTINUUM} Continuum.",
                rotten_baby = {
                    "50% chance to spawn a friendly blue fly when an attack damages an enemy (adds up with {c:7_SEALS} 7 Seals, up to 100%).",
                    "Current blue fly chance: %KRONOS_FLY%",
                },
                little_steven = "Gains homing effect.",
                rainbow_baby = "Gains {c:FRUIT_CAKE} Fruit Cake (first time only).",
                guardian_angel = "Gains +0.3 {{Speed}} speed.",
                censer = "Censer's smoke effect is fixed to player position.",
                leech = "Gains {c:CHARM_VAMPIRE} Charm of the Vampire (first time only).",
                bomb_bag = "Gains {c:PYRO} Pyro (first time only).",
                dark_bum = "Gains {c:MITRE} Mitre (first time only).",
                key_bum = "Gains {c:SKELETON_KEY} Skeleton Key (first time only).",
                abel = "Gains {c:MY_REFLECTION} My Reflection (first time only).",
                star_of_bethlehem = {
                    "Star of Bethlehem's aura is fixed to player position.",
                    "Gains {c:COMPASS} Compass (first time only).",
                },
                farting_baby = "Gains {c:JELLY_BELLY} Jelly Belly (first time only).",
                samsons_chains = "Gains {c:THUNDER_THIGHS} Thunder Thighs (first time only).",
                finger = "Gains {c:TRACTOR_BEAM} Tractor Beam (first time only).",
                little_chad = "Gains {c:CANDY_HEART} Candy Heart (first time only).",
                sack_of_pennies = "Gains {c:DOLLAR} Dollar (first time only).",
                sack_of_sacks = "Gains {c:SACK_HEAD} Sack Head (first time only).",
                charged_baby = "Gains {c:9_VOLT} 9 Volt (first time only).",
                yo_listen = "Gains {c:XRAY_VISION} X-Ray Vision (first time only).",
                daddy_longlegs = {
                    "10% chance for a leg to stomp when an attack damages an enemy, dealing 2x damage around it (stacks with each absorbed copy).",
                    "Current stomp chance: %KRONOS_STOMP%",
                },
                sister_maggy = "Gains {c:CRICKETS_HEAD} Cricket's Head (first time only).",
                little_chubby = "Gains {c:MARS} Mars (first time only).",
                big_chubby = {
                    "Gains {c:MARS} Mars (first time only).",
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                peeper = "Gains {c:MOMS_EYE} Mom's Eye (first time only).",
                bbf = "Gains {c:FIRE_MIND} Fire Mind (first time only).",
                fates_reward = "Gains {c:20_20} 20/20 (first time only).",
                lil_gurdy = "Gains {c:CHOCOLATE_MILK} Chocolate Milk (first time only).",
                bumbo = "Gains {c:PIGGY_BANK} Piggy Bank (first time only).",
                spider_mod = "Gains {c:SPIDER_BITE} Spider Bite (first time only).",
                depression = "Gains {c:HOLY_LIGHT} Holy Light (first time only).",
                king_baby = "Gains {c:MAGIC_MUSHROOM} Magic Mushroom (first time only).",
                acid_baby = "Gains {c:PHD} PHD (first time only).",
                jaw_bone = "Gains {c:COMPOUND_FRACTURE} Compound Fracture (first time only).",
                boiled_baby = "Gains {c:EYE_SORE} Eye Sore (first time only).",
                lil_dumpy = "Gains {c:JELLY_BELLY} Jelly Belly (first time only).",
                fruity_plum = "Gains {c:KIDNEY_STONE} Kidney Stone (first time only).",
                ["7_seals"] = {
                    "50% chance to spawn a friendly blue fly when an attack damages an enemy (adds up with {c:ROTTEN_BABY} Rotten Baby, up to 100%).",
                    "Current blue fly chance: %KRONOS_FLY%",
                },
                juicy_sack = {
                    "50% chance to spawn a friendly blue spider when an attack damages an enemy (adds up with {c:SISSY_LONGLEGS} Sissy Longlegs, up to 100%).",
                    "Current blue spider chance: %KRONOS_SPIDER%",
                },
                sissy_longlegs = {
                    "50% chance to spawn a friendly blue spider when an attack damages an enemy (adds up with {c:JUICY_SACK} Juicy Sack, up to 100%).",
                    "Current blue spider chance: %KRONOS_SPIDER%",
                },
                intruder = "Grants slowing effect to all attacks.",
                worm_friend = "Grants slowing effect to all attacks.",
                halo_of_flies = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                distant_admiration = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                cube_of_meat = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                forever_alone = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                sacrificial_dagger = {
                    "2% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                guppys_hairball = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                guillotine = {
                    "+1 {{Damage}}damage and +0.5 {{Tears}}fire rate (stacks with each absorbed copy).",
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                ball_of_bandages = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                smart_fly = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                best_bud = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                big_fan = {
                    "2% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                punching_bag = {
                    "2% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                sworn_protector = {
                    "5% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                friend_zone = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                lost_fly = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                hushy = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                moms_razor = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "{{BleedingOut}} 10% chance to make an enemy bleed when an attack damages it (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                    "Current bleed chance: %KRONOS_BLEED%",
                },
                angry_fly = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                leprosy = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                slipped_rib = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                pointy_rib = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                psy_fly = {
                    "5% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                tinytoma = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                headless_baby = "Gains {c:AQUARIUS} Aquarius (first time only).",
                cains_other_eye = "Gains {c:RUBBER_CEMENT} Rubber Cement (first time only).",
                papa_fly = "Gains {c:HIVE_MIND} Hive Mind (first time only).",
                shade = "Gains {c:LUSTY_BLOOD} Lusty Blood (first time only).",
                obsessed_fan = {
                    "1% chance to ignore damage from enemy projectiles (stacks with each absorbed copy).",
                    "Current projectile ignore chance: %KRONOS_BLOCK%",
                },
                gemini = "Deals 6 contact damage per second to touching enemies (stacks with each absorbed copy).",
                cube_baby = {
                    "{{Freezing}} 10% chance to freeze an enemy in place for 2 seconds when an attack damages it (stacks with each absorbed copy).",
                    "Current freeze chance: %KRONOS_FREEZE%",
                },
                lil_spewer = {
                    "25% chance to leave red creep under an enemy when an attack damages it (stacks with each absorbed copy).",
                    "Current creep chance: %KRONOS_CREEP%",
                },
                gb_bug = {
                    "When absorbed, returns a random half of the other absorbed familiars.",
                    "Returned familiars are not absorbed again.",
                },
                bum_friend = {
                    "10% chance to drop a random pickup on room clear (stacks with each absorbed copy).",
                    "Current pickup drop chance: %KRONOS_PICKUP_DROP%",
                },
                lil_chest = {
                    "{{Chest}} 10% chance to drop a chest on room clear (stacks with each absorbed copy).",
                    "Current chest drop chance: %KRONOS_CHEST_DROP%",
                },
                relic = "{{SoulHeart}} Drops a soul heart every 6 room clears (one more per absorbed copy).",
                mystery_sack = "Drops a random pickup every 6 room clears (one more per absorbed copy).",
                rune_bag = "{{Rune}} Drops a rune every 7 room clears (one more per absorbed copy).",
                paschal_candle = "{{Tears}} +0.03 fire rate per room clear (stacks with each absorbed copy).",
                holy_water = "Leaves holy water creep at the player's position when hit (one more per absorbed copy, up to 4).",
                dry_baby = {
                    "25% chance to trigger {c:NECRONOMICON} The Necronomicon when hit (stacks with each absorbed copy).",
                    "Current Necronomicon chance: %KRONOS_NECRONOMICON%",
                },
                milk = "{{Tears}} +1 fire rate for the rest of the floor after the first hit on it (stacks with each absorbed copy).",
                bird_cage = "Deals 45 damage to the nearest enemy when hit (stacks with each absorbed copy).",
                mystery_egg = "{{Friendly}} Spawns a charmed fly when hit (one more per absorbed copy, up to 5).",
                my_shadow = "{{Friendly}} Spawns a friendly black charger when hit (one more per absorbed copy, up to 3).",
                hallowed_ground = "Places a white poop nearby when hit.",
                lost_soul = "{{EternalHeart}} Drops an eternal heart after leaving a floor without getting hit (one more per absorbed copy).",
                bloodshot_eye = "Bloodshot Eye is fixed to the player's position.",
                mongo_baby = "Refills Minisaacs up to the number of absorbed copies on each room entry.",
                buddy_in_a_box = "Each floor, gains the absorbed effect of one random other familiar (one more per absorbed copy).",
                lil_delirium = "Each floor, gains the absorbed effect of one random other familiar (one more per absorbed copy).",
                box_of_friends = "On use, absorbed familiar effects are doubled for the room (no {c:DEMON_BABY} Demon Baby).",
                monster_manual = "Absorbs familiars summoned before or after obtaining Kronos, granting +2 Damage and their effects or item conversions for the floor. Room entry does not grant the absorption again.",
                sacrificial_altar = "On use, sacrifices up to 2 absorbed familiars to spawn devil room items.",
                trinket_the_twins = "50% chance on room entry to double one absorbed familiar's effect for the room.",
                ["1up"] = "Cannot be absorbed by {own:KRONOS} Kronos.",
                isaacs_heart = "Cannot be absorbed by {own:KRONOS} Kronos.",
                dead_cat = "Cannot be absorbed by {own:KRONOS} Kronos.",
                key_piece_1 = "Cannot be absorbed by {own:KRONOS} Kronos.",
                key_piece_2 = "Cannot be absorbed by {own:KRONOS} Kronos.",
                knife_piece_1 = "Cannot be absorbed by {own:KRONOS} Kronos.",
                knife_piece_2 = "Cannot be absorbed by {own:KRONOS} Kronos.",
                damocles_passive = "Cannot be absorbed by {own:KRONOS} Kronos.",
                straw_man = "Cannot be absorbed by {own:KRONOS} Kronos.",
                blood_oath = "Cannot be absorbed by {own:KRONOS} Kronos.",
            },
        },
        APPRAISAL_CERTIFICATE = {
            name = "Appraisal Certificate",
            description = "Is this a loot?",
            eid = {
                "Consumes {{Coin}} 30 to absorb all currently held trinkets and enter the {c:DEATH_CERTIFICATE} Death Certificate dimension containing every trinket except {own:ATROPOS} Atropos.",
                "#An always-open door back to the original room is on the left side of the first room.",
                "#{c:GLOWING_HOUR_GLASS} Glowing Hourglass cannot be used inside the Appraisal rooms.",
            },
            synergies = {
                atropos = {
                    "After taking one trinket in a room, only the remaining trinkets in that room disappear.",
                    "#The acquired trinket is absorbed, and you can choose one from each of the other rooms.",
                },
            },
        },
        MONEY_TEAR = {
            name = "Money = Tear",
            description = "Money is tears",
            eid = {
                "While held, gains +0.066 {{Tears}}SPS per coin.",
            },
        },
        UTILITY_BELT = {
            name = "Utility Belt",
            description = "It Item",
            eid = {
                "On pickup, moves your current active item to the pocket slot.",
                "#If pocket is already occupied, does nothing.",
                "#If no active, the next acquired active will be moved to the pocket slot.",
                "#{{Warning}} Some items cannot be moved.",
            },
            synergies = {
                book_of_virtues = "{{Warning}} This active cannot be moved to pocket slot",
                d_infinity = "{{Warning}} This active cannot be moved to pocket slot",
                blank_card = "{{Warning}} This active cannot be moved to pocket slot",
                placebo = "{{Warning}} This active cannot be moved to pocket slot",
                clear_rune = "{{Warning}} This active cannot be moved to pocket slot",
                glowing_hour_glass = "{{Warning}} This active cannot be moved to pocket slot",
                jar_of_wisps = "{{Warning}} This active cannot be moved to pocket slot",
            },
        },
        SEALED_DEMON_SWORD = {
            name = "Sealed Demon Sword",
            description = "Need more blood...",
            eid = {
                "{{Speed}} Movement speed -0.2",
                "#Enemies arrive already cleaved by {c:MEAT_CLEAVER} Meat Cleaver (2 copies at 40% health)",
                "#Bosses are not split",
                "#{{Warning}} After killing 300 enemies, evolves into {own:TYRFING} Tyrfing.",
                "#{{Warning}} REPENTOGON recommended",
            },
        },
        TYRFING = {
            name = "Tyrfing",
            description = "Cursed Demon Sword",
            eid = {
                "Gain +0.05 {{Damage}}Damage per enemy killed.",
                "#{{Warning}} Lose (50/stack) of accumulated damage when hit.",
            },
        },
        ICE_BREATH = {
            name = "Ice Breath",
            description = "Breath of frost",
            eid = {
                "After every (15-{{Luck}}Luck) attacks, fires ice flames",
                "#Fires up to {{Tears}} count per burst (minimum 1)",
                "#Ice flames deal 20% of your {{Damage}}Damage",
                "#On hit: {{Luck}}% chance to freeze (max 100%)",
                "#{{Warning}} Requires REPENTOGON!",
            },
        },
        FIRE_BREATH = {
            name = "Fire Breath",
            description = "Breath of flame",
            eid = {
                "After every (15-{{Luck}}Luck) attacks, fires flames",
                "#Fires up to {{Tears}} count per burst (minimum 1)",
                "#Flames deal 30% of your {{Damage}}Damage",
                "#On hit: ({{Luck}} x5)% chance to burn (max 100%)",
                "#{{Warning}} Requires REPENTOGON!",
            },
        },
        SOFLAM = {
            name = "SOFLAM",
            description = "Target acquired",
            eid = {
                "Replaces your tears with lasers",
                "#When your attack damages an enemy: 10% chance to designate the target (+{{Luck}}Luck x5%)",
                "#After 1.5 seconds, {c:EPIC_FETUS} Epic Fetus missiles strike one-by-one equal to your current multishot count",
                "#Missile deals 3 times your {{Damage}}Damage",
                "#{{Warning}} Requires REPENTOGON!",
            },
            synergies = {
                mr_mega = {
                    "Explosion radius gets a one-time x1.5 bonus",
                    "#Missile damage stacks as x2 per Mr. Mega copy",
                },
            },
        },
        TWO_FACED_PENNY = {
            name = "Two Faced Penny",
            description = "Probability is 100%!",
            eid = {
                "After pickup, your next item is duplicated once.",
                "#Clear a floor without taking damage to gain that item again.",
            },
        },
        INF_D6 = {
            name = "Inf D6",
            description = "Enjoy rerolling the dice whenever you want!",
            eid = {
                "Convenience item.",
            },
        },
        SEVERED_OATH = {
            name = "Severed Oath",
            description = "Cut the thread of fate",
            eid = {
                "On use, separates cycling items in the room into individual items.",
                "#{{Warning}} Requires REPENTOGON!",
            },
        },
        CEIL = {
            name = "Ceil",
            description = "Round it up!",
            eid = {
                "Rounds {{Speed}}Speed, {{Tears}}Tears, {{Damage}}Damage, {{Range}}Range, {{Shotspeed}}Shot Speed, and {{Luck}}Luck up.",
                "#Based on the second decimal place, rounds up if even 0.01 over.",
            },
        },
        ROUND = {
            name = "Round",
            description = "Halfway is enough",
            eid = {
                "Rounds {{Speed}}Speed, {{Tears}}Tears, {{Damage}}Damage, {{Range}}Range, {{Shotspeed}}Shot Speed, and {{Luck}}Luck to the nearest integer.",
                "#Based on the second decimal place, rounds up from 0.50.",
                "#Stats other than {{Luck}}Luck never become 0 and are at least 1.",
            },
            synergies = {
                ceil = "Ceil applies first, so Round has no effect.",
            },
        },
        FLOOR = {
            name = "Floor",
            description = "There is a floor",
            eid = {
                "Rounds {{Speed}}Speed, {{Tears}}Tears, {{Damage}}Damage, {{Range}}Range, {{Shotspeed}}Shot Speed, and {{Luck}}Luck down.",
                "#However, stats never drop below the character's base stats.",
                "#Modded characters use {{Player0}}Isaac's base stats.",
            },
            synergies = {
                ceil = "Ceil applies first; only the base stat guarantee is added.",
                round = "Round applies first; only the base stat guarantee is added.",
            },
        },

        -- Familiars
        TIME_MONEY = {
            name = "Time = Money",
            description = "Time is money",
            eid = {
                "Drops 5 coins on pickup.",
                "#Every 60 seconds, drops coins equal to 5% of current money (minimum 1).",
                "#Coins dropped by this familiar are replaced with nickel 5% of the time, golden coin 2% of the time, lucky coin 2% of the time, and dime 1% of the time.",
                "#The probability of the above is increased by (1+0.1×Luck{{Luck}}) times up to 4 times.",
                "#When taking damage, the number of coins dropped is reduced by 1.",
            },
            synergies = {
                bffs = "Drop rate increases to 10%.",
            },
        },

        -- Trinkets
        TIME_POWER = {
            name = "Time = Power",
            description = "Time is power",
            eid = {
                "While held, gains +0.006 {{Damage}}Damage per second.",
                "#On taking damage, gain is paused for 60 seconds.",
            },
        },
        TIME_TEAR = {
            name = "Time = Tear",
            description = "Time is tears",
            eid = {
                "While held, gains +0.0066 {{Tears}}SPS per second.",
                "#On taking damage, gain is paused for 60 seconds.",
            },
        },
        TIME_LUCK = {
            name = "Time = Luck",
            description = "Time is luck",
            eid = {
                "While held, gains +0.01 {{Luck}}Luck per second.",
                "#On taking damage, gain is paused for 60 seconds.",
            },
        },
        F_MINUS = {
            name = "F -",
            description = "Just avoiding the right answer is luck too.",
            eid = {
                "Luck increases by 5.",
                "#When moving to the next floor without taking damage, evolves into {own:C_MINUS} C -.",
            },
        },
        C_MINUS = {
            name = "C -",
            description = "BETTER LUCK NEXT TIME!",
            eid = {
                "Luck increases by 4.",
                "#{{Tears}} Fixed SPS increases by 2.0.",
                "#When moving to the next floor without taking damage, evolves into {own:B_MINUS} B -.",
            },
        },
        B_MINUS = {
            name = "B -",
            description = "Well begun is half done.",
            eid = {
                "Luck increases by 3.",
                "#{{Tears}}Fixed SPS increases by 3.0.",
                "#{{Damage}}Damage increases by 3.0.",
                "#When moving to the next floor without taking damage, evolves into {own:A_MINUS} A -.",
            },
        },
        A_MINUS = {
            name = "A -",
            description = "Nice try, did he?",
            eid = {
                "Luck increases by 2.",
                "#{{Tears}} Fixed SPS increases by 4.0.",
                "#{{Damage}} Damage increases by 4.0.",
                "#4x multipliers are distributed to Damage, Luck, and SPS. (No stacking)",
                "#Multipliers are at least 0.8x.",
                "#On hit, downgrades to {own:B_MINUS} B -.",
            },
        },
        ATROPOS = {
            name = "Atropos",
            description = "Broken Destiny",
            eid = {
                "Allows picking all optioned items",
                "#Adds +1 option to all items.",
                "#{{Warning}} REPENTOGON recommended",
            },
            synergies = {
                death_certificate = {
                    "A door back to the original room opens on the left side of the first room in the Death Certificate dimension.",
                    "#Drops a {card:FOOL} Fool card in the first room.",
                    "#After picking up an item, all other items in that room disappear, but you do not automatically return to the original room.",
                },
            },
        },
        ANGELS_CROWN = {
            name = "Angel's Crown",
            description = "Heavenly bargain",
            eid = {
                "Treasure Room items are replaced with {{AngelRoom}}Angel Room items, sold as {{Coin}}coin deals.",
                "#{{Warning}} REPENTOGON recommended",
            },
            specials = {
                append = {
                    "25% chance for the Angel Treasure Room to be blessed: one extra {{AngelRoom}}Angel Room item and an {{EternalHeart}}Eternal Heart",
                    "25% chance for the Angel Treasure Room to be blessed: one extra {{AngelRoom}}Angel Room item and an {{EternalHeart}}Eternal Heart",
                    "33% chance for the Angel Treasure Room to be blessed: one extra {{AngelRoom}}Angel Room item and an {{EternalHeart}}Eternal Heart",
                },
            },
        },
    },
    ui = {
        kronos = {
            transfer_damage = "Damage +2",
            transfer_return = "Familiar returned",
            transfer_pretty_fly = "Projectile ignore chance +%s%%",
        },
        conch_mode = {
            transform = "Conch mode %s: transforms into {{item_name}}",
            flags = {
                positive = "positive",
                neutral = "neutral",
                negative = "negative",
            },
        },
        injectable_steroids = {
            death_chance = "#{{ColorRed}}Current Death Chance: %s%%{{CR}}",
            floor_uses = " (Used this floor: %s times)",
        },
        sealed_demon_sword = {
            remaining_kills = "#{{ColorYellow}}Remaining kills: %s{{CR}}",
        },
        tyrfing = {
            accumulated_damage = "#{{Damage}} Accumulated damage: +%s",
        },
        utility_belt = {
            pocket_full = "#{{ColorRed}}Pocket slot already in use - cannot move{{CR}}",
            will_move = "#{{ColorGreen}}Will move: %s{{CR}}",
            no_active = "#{{ColorYellow}}No active - will move next acquired active{{CR}}",
        },
        void_dagger = {
            proc_chance = "#{{ColorYellow}}Current Proc Chance: %s%%{{CR}}",
            proc_detail = " (Base: %s%%, {{Luck}}x%s)",
        },
        mcm = {
            tab_general = "General",
            tab_spawn = "Spawn",
            options_title = "--- Conch's Blessing Options ---",
            spawn_title = "--- Spawn Settings ---",
            on = "ON",
            off = "OFF",
            debug_mode = "Debug Mode: %s",
            debug_mode_info = {
                "Enable debug output in the log and console.",
                "ON: show debug diagnostics",
                "OFF: hide debug diagnostics (default)",
            },
            reset = "Reset to Default",
            reset_info = {
                "Reset all settings to their default values.",
                "This applies immediately.",
            },
            spawn_collectibles = "Collectibles: %s",
            spawn_collectibles_info = {
                "Allow mod collectibles to spawn naturally.",
                "Default: OFF",
            },
            spawn_trinkets = "Trinkets: %s",
            spawn_trinkets_info = {
                "Allow mod trinkets to spawn naturally.",
                "Default: OFF",
            },
        },
    },
}
