-- Korean text for Conch's Blessing. Same layout as en.lua (read its header);
-- anything missing here falls back to English. Keep every entry line-for-line
-- parallel with en.lua, and run `python check_locale.py` after editing.
return {
    items = {
        -- Collectibles
        LIVE_EYE = {
            name = "살아있는 눈",
            description = "놓쳐도 괜찮아",
            eid = {
                "몬스터를 적중시킬때 마다 {{Damage}}데미지 배수가 0.1씩 증가합니다.",
                "#몬스터에 맞지 않으면 {{Damage}}데미지 배수가 0.15씩 감소합니다.",
                "#{{Luck}} 50% 확률로 감소하지 않습니다.(행운 1당 5%)",
                "#{{Damage}} 최대/최소 데미지 배수 (x3.0/x0.75)",
                "#눈물이 아닌 공격을 사용하면 {{Damage}}데미지 배수가 x1.5로 고정됩니다.",
            },
            synergies = {
                rock_bottom = "데미지 배수가 최대치인 x3.0으로 고정됩니다. (눈물이 아닌 공격이어도 동일)",
            },
        },
        VOID_DAGGER = {
            name = "공허의 단검",
            description = "공허가 열린다",
            eid = {
                "#내 공격으로 적에게 피해를 주면 확률로 그 위치에 내 데미지의 보이드 링을 소환합니다.",
                "#확률은 (30 - {{Tears}}연사)%로 5%보다 작아지지 않습니다",
                "#위 확률은 {{Luck}}운에 따라 (1+0.1×{{Luck}}운) 배수로 증가합니다. (최대 100%)",
                "#지속시간은 {{Damage}}데미지에 따라 증가하며 데미지 10당 5단계로 증가합니다.",
                "#{{BlackHeart}}블랙하트는 드랍되지 않습니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
        },
        ETERNAL_FLAME = {
            name = "영원한 불꽃",
            description = "정화의 불길",
            eid = {
                "저주가 걸릴 때마다 저주를 제거합니다.",
                "#저주 제거 시 고정 데미지 +3.0, 연사 +1.0을 영구적으로 부여합니다.",
                "#{{EternalHeart}} 이터널 하트 1개를 획득합니다.",
            },
        },
        POWER_TRAINING = {
            name = "파워 트레이닝",
            description = "라잇웨잇 베이비!",
            eid = {
                "사용시 데미지, 연사, 사거리, 행운이 1.0~1.3배가 됩니다.",
                "#최초 획득시 게이지가 절반 차 있습니다",
                "#중첩시 합연산으로 증가합니다.",
                "#최종 배수는 0.5 아래로 내려가지 않습니다.",
            },
        },
        ORAL_STEROIDS = {
            name = "경구형 스테로이드",
            description = "주사는 무서워",
            eid = {
                "획득시 데미지, 연사, 사거리, 행운이 0.8 ~ 1.5배가 됩니다.",
                "#중첩시 합연산으로 증가합니다.",
                "#최종 배수는 0.4 아래로 내려가지 않습니다.",
            },
        },
        INJECTABLE_STEROIDS = {
            name = "주사 스테로이드",
            description = "힘을 원해...",
            eid = {
                "사용시 데미지, 연사, 사거리, 행운이 0.5~2.0배가 됩니다.",
                "#최초 획득시 게이지가 절반 차 있습니다",
                "#중첩시 합연산으로 증가합니다.",
                "#최종 배수는 0.25 아래로 내려가지 않습니다.",
                "#{{Warning}} 몸이 점점 노래집니다...",
                "#{{Warning}} 기본 1% 확률로 즉사합니다.",
                "#{{Warning}} 즉사는 보호막과 무적을 무시하지만 부활은 정상 발동합니다.",
                "#{{Warning}} 사용시 즉사 확률이 3%씩 증가하고 층마다 초기화됩니다.",
                "#방 클리어시마다 즉사확률이 0.25% 감소합니다.",
            },
        },
        RAT = {
            name = "자",
            description = "자",
        },
        OX = {
            name = "축",
            description = "축",
        },
        TIGER = {
            name = "인",
            description = "인",
        },
        RABBIT = {
            name = "묘",
            description = "묘",
        },
        DRAGON = {
            name = "진",
            description = "날씨의 신",
            eid = {
                "공중과 지형관통을 얻습니다.",
                "#5번 공격마다 랜덤한 방향으로 번개구체를 5발 발사합니다",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
            synergies = {
                dragon = {
                    "전기 구체가 태풍으로 변합니다",
                    "#태풍이 멈추면 해당 위치에 소용돌이가 생성되어 2초간 적을 끌어당깁니다",
                    "#소용돌이가 사라질 때, 내 데미지의 25배의 폭발이 발생합니다",
                    "#중첩시 데미지 25% 증가",
                },
            },
        },
        SNAKE = {
            name = "사",
            description = "사",
        },
        HORSE = {
            name = "오",
            description = "오",
        },
        GOAT = {
            name = "미",
            description = "미",
        },
        MONKEY = {
            name = "신",
        },
        CHICKEN = {
            name = "유",
            description = "유",
        },
        DOG = {
            name = "술",
            description = "술",
        },
        PIG = {
            name = "해",
            description = "해",
        },
        KRONOS = {
            name = "크로노스",
            description = "자식을 삼키다",
            eid = {
                "패밀리어를 흡수하여 고유능력과 데미지 2를 얻습니다",
                "#일부 패밀리어는 제외 목록에 따라 흡수되지 않습니다",
                "#현재 탄환 무시 확률: %KRONOS_BLOCK%",
            },
            synergies = {
                twisted_pair = "37.5% 데미지의 공격을 2개 추가합니다.",
                succubus = "내 주변으로 오라가 고정됩니다.",
                incubus = "75% 데미지의 공격을 1개 추가합니다.",
                seraphim = {
                    "공중, 지형관통 효과를 얻습니다.",
                    "{c:SACRED_HEART} 신성한 심장을 획득합니다. (최초 1회)",
                },
                robo_baby = "{c:TECHNOLOGY} 테크를 얻습니다.",
                robo_baby_2 = "{c:TECHNOLOGY_2} 테크 2를 얻습니다.",
                blue_babys_only_friend = "{c:LUDOVICO_TECHNIQUE} 루도비코를 얻습니다. (최초 1회)",
                lil_brimstone = "{c:BRIMSTONE} 혈사를 얻습니다.",
                bobs_brain = "{c:IPECAC} 구토제를 얻습니다. (최초 1회)",
                lil_monstro = "{c:MONSTROS_LUNG} 몬스트로의 폐를 얻습니다. (최초 1회)",
                lil_haunt = "모든 공격에 공포 효과를 부여합니다.",
                blood_puppy = "{c:GIMPY} 김피를 얻습니다. (최초 1회)",
                angelic_prism = "공격이 4갈래로 갈라져 나갑니다.",
                bot_fly = "{c:LOST_CONTACT} 잃어버린 렌즈를 얻습니다. (최초 1회)",
                freezer_baby = "{c:URANUS} 천왕성을 얻습니다. (최초 1회)",
                lil_abaddon = "{c:MAW_OF_THE_VOID} 공허의 구렁텅이를 얻습니다. (최초 1회)",
                multidimensional_baby = "{c:20_20} 20/20을 얻습니다.",
                harlequin_baby = "{c:THE_WIZ} 법사를 얻습니다.",
                brother_bobby = "{{Tears}} 고정연사 +2를 얻습니다.",
                demon_baby = "{c:MARKED} 표식을 얻습니다. (최초 1회)",
                little_gish = "모든 공격에 느림 효과를 부여합니다.",
                lil_loki = "{c:LOKIS_HORNS} 로키의 뿔을 얻습니다.",
                ghost_baby = "{c:CONTINUUM} 연속체를 얻습니다.",
                rotten_baby = {
                    "공격이 적에게 피해를 주면 50% 확률로 아군 파리를 소환합니다. ({c:7_SEALS} 7개의 도장과 합산, 최대 100%)",
                    "현재 아군 파리 소환 확률: %KRONOS_FLY%",
                },
                little_steven = "유도 효과를 얻습니다.",
                rainbow_baby = "{c:FRUIT_CAKE} 과일 케이크를 얻습니다. (최초 1회)",
                guardian_angel = "이동 속도{{Speed}} +0.3을 얻습니다.",
                censer = "향로의 오라 효과가 플레이어 위치에 고정됩니다.",
                leech = "{c:CHARM_VAMPIRE} 흡혈귀의 부적을 얻습니다. (최초 1회)",
                bomb_bag = "{c:PYRO} 파이로를 얻습니다. (최초 1회)",
                dark_bum = "{c:MITRE} 주교관을 얻습니다. (최초 1회)",
                key_bum = "{c:SKELETON_KEY} 해골 열쇠를 얻습니다. (최초 1회)",
                abel = "{c:MY_REFLECTION} 거울을 얻습니다. (최초 1회)",
                star_of_bethlehem = {
                    "베들레헴의 별 오라가 플레이어 위치에 고정됩니다.",
                    "{c:COMPASS} 나침반을 얻습니다. (최초 1회)",
                },
                farting_baby = "{c:JELLY_BELLY} 젤리 배를 얻습니다. (최초 1회)",
                samsons_chains = "{c:THUNDER_THIGHS} 천둥 허벅지를 얻습니다. (최초 1회)",
                finger = "{c:TRACTOR_BEAM} 트랙터 빔을 얻습니다. (최초 1회)",
                little_chad = "{c:CANDY_HEART} 캔디 하트를 얻습니다. (최초 1회)",
                sack_of_pennies = "{c:DOLLAR} 달러를 얻습니다. (최초 1회)",
                sack_of_sacks = "{c:SACK_HEAD} 자루 머리를 얻습니다. (최초 1회)",
                charged_baby = "{c:9_VOLT} 9볼트를 얻습니다. (최초 1회)",
                yo_listen = "{c:XRAY_VISION} 엑스레이 투시를 얻습니다. (최초 1회)",
                daddy_longlegs = {
                    "공격이 적에게 피해를 주면 10% 확률로 다리가 내려찍어 주변 적에게 공격력 x2의 피해를 줍니다. (흡수할 때마다 누적)",
                    "현재 내려찍기 확률: %KRONOS_STOMP%",
                },
                sister_maggy = "{c:CRICKETS_HEAD} 크리켓의 머리를 얻습니다. (최초 1회)",
                little_chubby = "{c:MARS} 화성을 얻습니다. (최초 1회)",
                big_chubby = {
                    "{c:MARS} 화성을 얻습니다. (최초 1회)",
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                peeper = "{c:MOMS_EYE} 엄마의 눈알을 얻습니다. (최초 1회)",
                bbf = "{c:FIRE_MIND} 불타는 마음을 얻습니다. (최초 1회)",
                fates_reward = "{c:20_20} 시력 2.0을 얻습니다. (최초 1회)",
                lil_gurdy = "{c:CHOCOLATE_MILK} 초콜릿 우유를 얻습니다. (최초 1회)",
                bumbo = "{c:PIGGY_BANK} 돼지 저금통을 얻습니다. (최초 1회)",
                spider_mod = "{c:SPIDER_BITE} 거미물림을 얻습니다. (최초 1회)",
                depression = "{c:HOLY_LIGHT} 신성한 빛을 얻습니다. (최초 1회)",
                king_baby = "{c:MAGIC_MUSHROOM} 마법의 버섯을 얻습니다. (최초 1회)",
                acid_baby = "{c:PHD} 박사학위를 얻습니다. (최초 1회)",
                jaw_bone = "{c:COMPOUND_FRACTURE} 복합 골절을 얻습니다. (최초 1회)",
                boiled_baby = "{c:EYE_SORE} 흉물을 얻습니다. (최초 1회)",
                lil_dumpy = "{c:JELLY_BELLY} 젤리 배를 얻습니다. (최초 1회)",
                fruity_plum = "{c:KIDNEY_STONE} 신장 결석을 얻습니다. (최초 1회)",
                ["7_seals"] = {
                    "공격이 적에게 피해를 주면 50% 확률로 아군 파리를 소환합니다. ({c:ROTTEN_BABY} 썩은 아기와 합산, 최대 100%)",
                    "현재 아군 파리 소환 확률: %KRONOS_FLY%",
                },
                juicy_sack = {
                    "공격이 적에게 피해를 주면 50% 확률로 아군 거미를 소환합니다. ({c:SISSY_LONGLEGS} 눈나 거미와 합산, 최대 100%)",
                    "현재 아군 거미 소환 확률: %KRONOS_SPIDER%",
                },
                sissy_longlegs = {
                    "공격이 적에게 피해를 주면 50% 확률로 아군 거미를 소환합니다. ({c:JUICY_SACK} 축축한 알집과 합산, 최대 100%)",
                    "현재 아군 거미 소환 확률: %KRONOS_SPIDER%",
                },
                intruder = "모든 공격에 느림 효과를 부여합니다.",
                worm_friend = "모든 공격에 느림 효과를 부여합니다.",
                halo_of_flies = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                distant_admiration = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                cube_of_meat = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                forever_alone = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                sacrificial_dagger = {
                    "적의 탄환에 맞을 때 2% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                guppys_hairball = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                guillotine = {
                    "{{Damage}}공격력 +1, {{Tears}}연사 +0.5 (흡수할 때마다 누적)",
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                ball_of_bandages = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                smart_fly = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                best_bud = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                big_fan = {
                    "적의 탄환에 맞을 때 2% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                punching_bag = {
                    "적의 탄환에 맞을 때 2% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                sworn_protector = {
                    "적의 탄환에 맞을 때 5% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                friend_zone = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                lost_fly = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                hushy = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                moms_razor = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "{{BleedingOut}} 공격이 적에게 피해를 주면 10% 확률로 출혈시킵니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                    "현재 출혈 확률: %KRONOS_BLEED%",
                },
                angry_fly = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                leprosy = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                slipped_rib = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                pointy_rib = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                psy_fly = {
                    "적의 탄환에 맞을 때 5% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                tinytoma = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                headless_baby = "{c:AQUARIUS} 물병자리를 얻습니다. (최초 1회)",
                cains_other_eye = "{c:RUBBER_CEMENT} 고무 접착제를 얻습니다. (최초 1회)",
                papa_fly = "{c:HIVE_MIND} 군체의식을 얻습니다. (최초 1회)",
                shade = "{c:LUSTY_BLOOD} 욕망의 피를 얻습니다. (최초 1회)",
                obsessed_fan = {
                    "적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적)",
                    "현재 탄환 무시 확률: %KRONOS_BLOCK%",
                },
                gemini = "접촉한 적에게 초당 6의 피해를 줍니다. (흡수할 때마다 누적)",
                cube_baby = {
                    "{{Freezing}} 공격이 적에게 피해를 주면 10% 확률로 적을 2초간 얼려 멈춥니다. (흡수할 때마다 누적)",
                    "현재 빙결 확률: %KRONOS_FREEZE%",
                },
                lil_spewer = {
                    "공격이 적에게 피해를 주면 25% 확률로 적 위치에 빨간 장판이 생깁니다. (흡수할 때마다 누적)",
                    "현재 장판 생성 확률: %KRONOS_CREEP%",
                },
                gb_bug = {
                    "흡수 시 지금까지 흡수한 다른 패밀리어 중 무작위로 절반을 되돌려줍니다.",
                    "되돌아온 패밀리어는 다시 흡수되지 않습니다.",
                },
                bum_friend = {
                    "방 클리어 시 10% 확률로 랜덤 픽업을 드랍합니다. (흡수할 때마다 누적)",
                    "현재 픽업 드랍 확률: %KRONOS_PICKUP_DROP%",
                },
                lil_chest = {
                    "{{Chest}} 방 클리어 시 10% 확률로 상자를 드랍합니다. (흡수할 때마다 누적)",
                    "현재 상자 드랍 확률: %KRONOS_CHEST_DROP%",
                },
                relic = "{{SoulHeart}} 방 6개 클리어마다 소울하트를 드랍합니다. (흡수할 때마다 1개씩 추가)",
                mystery_sack = "방 6개 클리어마다 랜덤 픽업을 드랍합니다. (흡수할 때마다 1개씩 추가)",
                rune_bag = "{{Rune}} 방 7개 클리어마다 룬을 드랍합니다. (흡수할 때마다 1개씩 추가)",
                paschal_candle = "{{Tears}} 방 클리어 시마다 연사 +0.03 (흡수할 때마다 누적)",
                holy_water = "피격 시 캐릭터 위치에 성수 장판이 생깁니다. (흡수할 때마다 1개씩 추가, 최대 4개)",
                dry_baby = {
                    "피격 시 25% 확률로 {c:NECRONOMICON} 네크로노미콘이 발동합니다. (흡수할 때마다 누적)",
                    "현재 네크로노미콘 발동 확률: %KRONOS_NECRONOMICON%",
                },
                milk = "{{Tears}} 스테이지에서 처음 피격 시 그 스테이지 동안 연사 +1 (흡수할 때마다 누적)",
                bird_cage = "피격 시 가장 가까운 적에게 45의 피해를 줍니다. (흡수할 때마다 누적)",
                mystery_egg = "{{Friendly}} 피격 시 매혹된 아군 파리를 소환합니다. (흡수할 때마다 1마리씩 추가, 최대 5마리)",
                my_shadow = "{{Friendly}} 피격 시 검은색 아군 애벌레를 소환합니다. (흡수할 때마다 1마리씩 추가, 최대 3마리)",
                hallowed_ground = "피격 시 근처에 하얀 똥을 설치합니다.",
                lost_soul = "{{EternalHeart}} 피격 없이 스테이지를 넘어가면 이터널하트를 드랍합니다. (흡수할 때마다 1개씩 추가)",
                bloodshot_eye = "피눈물 눈알이 플레이어 위치에 고정됩니다.",
                mongo_baby = "방에 들어갈 때마다 미니 아이작을 흡수한 수만큼 채워줍니다.",
                buddy_in_a_box = "스테이지마다 다른 패밀리어 하나의 흡수 효과를 무작위로 얻습니다. (흡수할 때마다 1개씩 추가)",
                lil_delirium = "스테이지마다 다른 패밀리어 하나의 흡수 효과를 무작위로 얻습니다. (흡수할 때마다 1개씩 추가)",
                box_of_friends = "사용 시 그 방에서 흡수 공격력과 고유능력이 2배가 됩니다. 방을 나가거나 이어하기 시 해제되며 변환 아이템은 추가 지급하지 않습니다.",
                monster_manual = "크로노스 획득 전후에 소환한 패밀리어를 흡수해 그 스테이지 동안 데미지 +2와 고유 효과 또는 변환 아이템을 얻습니다. 방 이동으로 같은 흡수 보상을 다시 얻지 않습니다.",
                sacrificial_altar = "사용 시 흡수한 패밀리어를 최대 2마리 제물로 바쳐 악마방 아이템을 생성합니다.",
                trinket_the_twins = "방 입장 시 50% 확률로 그 방에서 흡수한 패밀리어 하나의 효과가 2배가 됩니다.",
                ["1up"] = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                isaacs_heart = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                dead_cat = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                key_piece_1 = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                key_piece_2 = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                knife_piece_1 = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                knife_piece_2 = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                damocles_passive = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                straw_man = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
                blood_oath = "{own:KRONOS} 크로노스에 흡수되지 않습니다.",
            },
        },
        APPRAISAL_CERTIFICATE = {
            name = "감정 평가서",
            description = "이거 장물 아니죠?",
            eid = {
                "{{Coin}} 30원을 소비하여 현재 들고 있는 장신구를 모두 흡수하고 {own:ATROPOS} 아트로포스를 제외한 모든 장신구가 진열된 {c:DEATH_CERTIFICATE} 사망 증명서 차원으로 이동합니다.",
                "#첫 번째 방의 왼쪽에는 원래 방으로 돌아가는 문이 항상 열려 있습니다.",
                "#감정 평가서 공간 안에서는 {c:GLOWING_HOUR_GLASS} 빛나는 모래시계를 사용할 수 없습니다.",
            },
            synergies = {
                atropos = {
                    "각 방에서 장신구 하나를 획득하면 그 방에 남은 장신구만 사라집니다.",
                    "#획득한 장신구는 흡수되며, 다른 방에서도 하나씩 고를 수 있습니다.",
                },
            },
        },
        MONEY_TEAR = {
            name = "돈 = 연사",
            description = "돈은 연사다",
            eid = {
                "소지하고 있는 동전당 고정연사가 0.066 증가합니다.",
            },
        },
        UTILITY_BELT = {
            name = "다용도 벨트",
            description = "잇 아이템",
            eid = {
                "획득 시 현재 액티브 아이템을 포켓 슬롯으로 이동합니다.",
                "#포켓 슬롯이 이미 차있다면 이동하지 않습니다.",
                "#액티브 아이템이 없다면 다음 획득하는 액티브를 포켓 슬롯으로 이동합니다.",
                "#{{Warning}} 일부 아이템은 이동할 수 없습니다.",
            },
            synergies = {
                book_of_virtues = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
                d_infinity = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
                blank_card = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
                placebo = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
                clear_rune = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
                glowing_hour_glass = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
                jar_of_wisps = "{{Warning}} 해당 액티브는 포켓 슬롯으로 이동되지 않습니다",
            },
        },
        SEALED_DEMON_SWORD = {
            name = "봉인된 마검",
            description = "더 많은 피가 필요해...",
            eid = {
                "{{Speed}} 이동속도가 -0.2 감소합니다.",
                "#적이 {c:MEAT_CLEAVER} 고기 도축칼로 쪼개진 상태로 등장합니다. (체력 40%, 2마리)",
                "#보스는 쪼개지지 않습니다.",
                "#{{Warning}} 몬스터를 300마리 처치하면 {own:TYRFING} 티르핑으로 진화합니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
        },
        TYRFING = {
            name = "티르핑",
            description = "저주받은 마검",
            eid = {
                "몬스터 처치 시마다 {{Damage}}공격력이 +0.05 증가합니다.",
                "#{{Warning}} 피격 시 누적된 공격력의 50%를 잃습니다.",
            },
        },
        ICE_BREATH = {
            name = "아이스 브레스",
            description = "서리의 숨결",
            eid = {
                "(15-{{Luck}}운)번 공격마다 얼음 불꽃 발사",
                "#한 번에 최대 {{Tears}}연사 수치만큼 발사 (최소 1개)",
                "#얼음 불꽃은 내 {{Damage}}데미지의 20%",
                "#적중 시 {{Luck}}운% 확률로 빙결 (최대 100%)",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
        },
        FIRE_BREATH = {
            name = "파이어 브레스",
            description = "작열의 숨결",
            eid = {
                "(15-{{Luck}}운)번 공격마다 불꽃 발사",
                "#한 번에 최대 {{Tears}}연사 수치만큼 발사 (최소 1개)",
                "#불꽃은 내 {{Damage}}데미지의 30%",
                "#적중 시 ({{Luck}}운 x5)% 확률로 화상 (최대 100%)",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
        },
        SOFLAM = {
            name = "SOFLAM",
            description = "타겟 조준 완료",
            eid = {
                "기본 눈물이 레이저로 대체됩니다",
                "#내 공격으로 적에게 피해를 주면 10% 확률로 타겟이 지정됩니다 ({{Luck}}운 x5% 추가)",
                "#타겟으로 지정되면 1.5초 뒤 현재 멀티샷 수만큼 {c:EPIC_FETUS} Epic Fetus 미사일이 1발씩 연속으로 떨어집니다",
                "#미사일은 내 {{Damage}}공격력의 3배 데미지",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
            synergies = {
                mr_mega = {
                    "폭발 범위가 1.5배가 됩니다 (1회)",
                    "#미사일 데미지가 Mr. Mega 개수만큼 2배씩 중첩됩니다",
                },
            },
        },
        TWO_FACED_PENNY = {
            name = "양면 동전",
            description = "확률은 100%!",
            eid = {
                "획득 후 다음 액티브가 아닌 아이템을 하나 더 획득합니다.",
                "#피격 없이 층을 클리어하면 해당 아이템을 하나 더 획득합니다.",
            },
        },
        INF_D6 = {
            name = "무한 주사위",
            description = "마음대로 골라먹는 재미!",
            eid = {
                "편의성 아이템",
            },
        },
        SEVERED_OATH = {
            name = "적사단지",
            description = "이어진 운명을 끊다",
            eid = {
                "소지 중 방 진입 시 아이템의 순환 선택지를 1개 추가합니다.",
                "#기존 순환 선택지에 중첩됩니다. 적사단지 자체가 황금 강화되어 있으면 2개 추가합니다.",
                "#사용 시 방 안의 순환 아이템을 독립된 아이템으로 분리합니다.",
                "#{{Warning}} REPENTOGON이 필요합니다!",
            },
        },
        CEIL = {
            name = "올림",
            description = "모자라면 채운다!",
            eid = {
                "{{Speed}}이동속도, {{Tears}}연사, {{Damage}}공격력, {{Range}}사거리, {{Shotspeed}}탄속, {{Luck}}행운을 올림합니다.",
                "#소수점 둘째 자리 기준으로 0.01이라도 넘으면 올라갑니다.",
            },
        },
        ROUND = {
            name = "반올림",
            description = "반만 넘으면 된다",
            eid = {
                "{{Speed}}이동속도, {{Tears}}연사, {{Damage}}공격력, {{Range}}사거리, {{Shotspeed}}탄속, {{Luck}}행운을 반올림합니다.",
                "#소수점 둘째 자리 기준으로 0.50부터 올라갑니다.",
                "#{{Luck}}행운을 제외한 스탯은 0이 되지 않고 최소 1이 됩니다.",
            },
            synergies = {
                ceil = "올림이 먼저 적용되므로 반올림은 효과가 없습니다.",
            },
        },
        FLOOR = {
            name = "내림",
            description = "바닥은 있다",
            eid = {
                "{{Speed}}이동속도, {{Tears}}연사, {{Damage}}공격력, {{Range}}사거리, {{Shotspeed}}탄속, {{Luck}}행운을 내림합니다.",
                "#단, 캐릭터의 기본 스탯보다 낮아지지 않습니다.",
                "#모드 캐릭터는 {{Player0}}아이작의 기본 스탯을 기준으로 합니다.",
            },
            synergies = {
                ceil = "올림이 먼저 적용되고, 기본 스탯 보장만 추가로 적용됩니다.",
                round = "반올림이 먼저 적용되고, 기본 스탯 보장만 추가로 적용됩니다.",
            },
        },

        -- Familiars
        TIME_MONEY = {
            name = "시간 = 돈",
            description = "시간은 돈이다",
            eid = {
                "동전 5개를 드랍합니다.",
                "#60초마다 현재 소지중인 동전의 5% 개수만큼 동전을 드랍합니다. (최소 1개)",
                "#이 패밀리어가 드랍하는 동전은 5% 확률로 5원, 2% 확률로 황금 동전, 2% 확률로 행운 동전, 1% 확률로 10원으로 대체됩니다.",
                "#행운에 따라 위 확률이 (1+0.1×운{{Luck}})배로 4배까지 증가합니다.",
                "#피격시 드랍되는 동전의 갯수가 1개 감소합니다.",
            },
            synergies = {
                bffs = "동전 드랍 비율이 10%로 증가합니다.",
            },
        },

        -- Trinkets
        TIME_POWER = {
            name = "시간 = 힘",
            description = "시간은 힘이다",
            eid = {
                "소지 중 초당 {{Damage}}공격력이 0.006 증가합니다.",
                "#적에게 피격 시 60초 동안 증가가 중지됩니다.",
            },
        },
        TIME_TEAR = {
            name = "시간 = 연사",
            description = "시간은 연사다",
            eid = {
                "소지 중 초당 {{Tears}}고정연사가 0.0066 증가합니다.",
                "#적에게 피격 시 60초 동안 증가가 중지됩니다.",
            },
        },
        TIME_LUCK = {
            name = "시간 = 행운",
            description = "시간은 행운이다",
            eid = {
                "소지 중 초당 {{Luck}}운이 0.01 증가합니다.",
                "#적에게 피격 시 60초 동안 증가가 중지됩니다.",
            },
        },
        F_MINUS = {
            name = "F -",
            description = "정답만 피하는 것도 행운이야",
            eid = {
                "행운이 5 증가합니다.",
                "#피격 당하지 않은 채로 다음 층으로 이동 시, {own:C_MINUS} C -로 진화합니다.",
            },
        },
        C_MINUS = {
            name = "C -",
            description = "그럴 수 있어. 이런 날도 있는 거지 뭐.",
            eid = {
                "행운이 4 증가합니다.",
                "#{{Tears}} 고정연사가 2.0 증가합니다.",
                "#피격 당하지 않은 채로 다음 층으로 이동 시, {own:B_MINUS} B -로 진화합니다.",
            },
        },
        B_MINUS = {
            name = "B -",
            description = "시작이 반이다",
            eid = {
                "행운이 3 증가합니다.",
                "#{{Tears}} 고정 연사가 3.0 증가합니다.",
                "#{{Damage}} 공격력이 3.0 증가합니다.",
                "#피격 당하지 않은 채로 다음 층으로 이동 시, {own:A_MINUS} A -로 진화합니다.",
            },
        },
        A_MINUS = {
            name = "A -",
            description = "좋은 시도였어. 아이작",
            eid = {
                "행운이 2 증가합니다.",
                "#{{Tears}} 고정연사가 4.0 증가합니다.",
                "#{{Damage}} 공격력이 4.0 증가합니다.",
                "#4배수가 공격력, 행운, 연사에 나눠서 적용됩니다. (중첩X)",
                "#0.8배이상으로 나눠서 적용됩니다.",
                "#피격 시 {own:B_MINUS} B -로 강등됩니다.",
            },
        },
        ATROPOS = {
            name = "아트로포스",
            description = "끊어진 운명",
            eid = {
                "모든 선택지 아이템을 획득할 수 있게 합니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
            synergies = {
                death_certificate = {
                    "사망 증명서 공간의 첫 방 왼쪽에 원래 방으로 돌아가는 문이 열립니다.",
                    "#아이템 하나를 획득하면 해당 방에 남은 아이템이 모두 사라지지만, 자동으로 원래 방으로 돌아가지는 않습니다.",
                },
            },
        },
        ANGELS_CROWN = {
            name = "천사의 왕관",
            description = "천상의 거래",
            eid = {
                "보물방 아이템이 {{AngelRoom}}천사방 아이템으로 바뀌고, {{Coin}}동전으로 사는 상점 거래가 됩니다.",
                "#{{Warning}} REPENTOGON 권장",
            },
            specials = {
                append = {
                    "25% 확률로 축복받은 보물방이 되어 {{AngelRoom}}천사방 아이템 1개와 {{EternalHeart}}영원한 하트가 추가됩니다.",
                    "25% 확률로 축복받은 보물방이 되어 {{AngelRoom}}천사방 아이템 1개와 {{EternalHeart}}영원한 하트가 추가됩니다.",
                    "33% 확률로 축복받은 보물방이 되어 {{AngelRoom}}천사방 아이템 1개와 {{EternalHeart}}영원한 하트가 추가됩니다.",
                },
            },
        },
    },
    ui = {
        percent = {
            standard = "%s%%",
            zero = "0%%",
            unit1 = "%s할",
            unit2 = "%s푼",
            unit3 = "%s리",
            unit4 = "%s모",
            separator = " ",
            negative = "-%s",
        },
        kronos = {
            transfer_damage = "데미지 +2",
            transfer_return = "패밀리어 반환",
            transfer_pretty_fly = "탄환 무시 확률 +%s",
        },
        conch_mode = {
            transform = "소라고둥 모드 %s시 {{item_name}}으로 변환",
            flags = {
                positive = "긍정",
                neutral = "중립",
                negative = "부정",
            },
        },
        injectable_steroids = {
            death_chance = "#{{ColorRed}}현재 즉사 확률: %s{{CR}}",
            floor_uses = " (이번 층 사용: %s회)",
        },
        sealed_demon_sword = {
            remaining_kills = "#{{ColorYellow}}남은 처치 수: %s{{CR}}",
        },
        tyrfing = {
            accumulated_damage = "#{{Damage}} 누적 공격력: +%s",
        },
        utility_belt = {
            pocket_full = "#{{ColorRed}}포켓 슬롯이 이미 사용 중 - 이동 불가{{CR}}",
            will_move = "#{{ColorGreen}}획득 시 이동: %s{{CR}}",
            no_active = "#{{ColorYellow}}현재 액티브 없음 - 다음 획득 액티브를 이동{{CR}}",
        },
        void_dagger = {
            proc_chance = "#{{ColorYellow}}현재 발동 확률: %s{{CR}}",
            proc_detail = " (기본: %s, {{Luck}}x%s)",
        },
    },
}
