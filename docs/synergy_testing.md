# 시너지·조건·실제 피해 검사표

현재 상태: **테스트 코드 작성 및 오프라인 검증 완료 / 이번 확장본 게임 실행 대기**.
설명에 등록된 시너지 144개를 빠짐없이 실행 명령에 연결했다. 연결 개수는 PASS 개수가 아니다.
전체 `conch_test`는 현재 105개 벤치이며, 기존 상세 검사와 중복되는 명령은 한 번만 실행한다.
크로노스 지급형 48종·차단형 22종·제외형 10종은 각각 `conversions`·`barriers`·`exclusions`로 묶어
전종의 복사본·기여량·반환을 같은 런에서 검사한다. 추가 30종은 `attacks`(13)·`auras`(7)·`abilities`(10) 순차 묶음으로 실행하며, 벨트 제외 액티브 7종은 `excluded_actives` 한 묶음으로 실행한다. 아래 개별 명령은 문제 재현용으로 유지하며 기본 실행에서는 중복하지 않는다.

## 이번에 추가한 실제 검증

| 대상 | 조건·시너지 | 관찰하는 결과 |
| --- | --- | --- |
| 전 아이템 기본 검사 | 1개→2개→1개→0개→재획득→제거 | 실제 스탯, 인벤토리, 남은 효과. 상세 범위는 item_testing.md |
| 스탯 반응 25종 | 보유 중 여섯 스탯 증가→원복 | 실제 스탯·발사 간격·생성 수·피해량·확률 훅; 훅 검사는 엔진 확률 검증과 구분 |
| Fire / Ice Breath | 0%→100%→0% 상태 이상 확률 | 실제 HP 감소, 화상·빙결 부여/비부여와 만료 |
| Dragon | 1개 번개·2개 이상 회오리, 공격력 변화 | 직접 타격 HP, 소용돌이 전환·당김·실제 2초 수명·종료 25배 폭발·범위 밖 비피해 |
| Void Dagger | 공격력·연사·행운·중첩·제거 | 같은 공격의 중복 발동 억제, 실제 고리 HP 피해, 피해 속성·지속시간 |
| SOFLAM | Mr. Mega 0→1→2→0, 20/20, 제거 | 실제 레이저 적중 뒤 총 미사일 HP 피해, 45업데이트 지연과 정산 상한, 범위 내/밖, 대기 중 제거 시 후속 피해 취소 |
| Live Eye | 눈물/Brimstone·Rock Bottom 조합 | 적용 배율과 시너지 전부 제거 후 실제 공격력 원복 |
| Utility Belt | 제외 액티브 7개, 양쪽 획득 순서 | 주 슬롯 보존·포켓 미이동 |
| Ceil / Round / Floor | 각 조합의 양쪽 획득 순서·제거 | 여섯 실제 스탯의 우선순위·원복 |
| F-/C-/B-/A- | 일반·황금, 피격/무피격 층 이동 | 진화·강등 실물 장신구 및 이전 효과 회수 |
| F-/C-/B-, Time=Power/Tear/Luck | 일반·황금 + 엄마의 상자 획득·제거 | 바닐라 상자 자체 스탯과 분리한 스탯·성장률 |
| Time=Power/Tear/Luck | 피격·가속 1800틱 경계·드롭 | 성장 정지/재개, 누적분 유지·드롭 후 성장 정지 |
| Time=Money | BFFS 0→1→2→0, 코인·피격 페널티 | 최초 5개·가속 1800틱마다 실제 생성 코인 수, 최소 1개, 마지막 제거 후 미생성 |
| Two Faced Penny | 액티브→패시브 획득, 무피격/피격 층 이동 | 액티브 복제·예약 소비 없음, 다음 패시브 복제, 층 보상 지급/미지급 |
| Atropos + Death Certificate | 실제 사용·선택·귀환문 통과 | 귀환문 생성·카드 미지급·제거 후 문 유지, 획득 대기열 수락 즉시 그 방 아이템 소멸·자동 귀환 억제·원래 방 귀환 |
| Appraisal + Atropos | 기존 conch_test appraisal detail 상세 검사 | 실제 보상 획득·방당 한 번·체류·정산 |
| Kronos 공통 | 펫마다 1·2개 흡수, 마지막 제거 | 각 +2, 제외 목록, 전환 아이템 지급 한도, 기존 소유 아이템 보존·펫 반환 |
| Kronos 공격 발동 | 명중·100% 중첩, 바리어의 실제 적 탄환/일반 피격 | 밟기·파리·거미·장판 실제 HP, 상태 이상, 적 탄환 차단 |
| Kronos 피격 발동 | 실제 피격·중첩 상한·재피격 | 성수·아군 생성, Necronomicon/Bird Cage HP, Milk 중복 억제·층 초기화, 흰 똥 |
| Kronos 클리어·층 조건 | 실제 적 사망 클리어 + 엔진 보상, 6/7회 경계 | 픽업 개수·종류, Paschal 연사, Lost Soul 무피격 보상/피격 취소 |
| Kronos 고정 펫 | 흡수·사라짐·다시 생성 | 고정 위치·개수, 향로 근거리 감속/원거리 비감속, 서큐버스 피해, 별 스탯 |
| Kronos 추가 발사 | Incubus·Twisted Pair·Prism | 실제 발사·피해 비율·HP 감소; Prism 분열 발생 |
| Kronos 일시 효과 | Monster Manual 선/후 획득·방/층 이동, Box, Twins, Altar | 실제 스탯·중복 적립 방지·층 만료·희생 보상과 영구 반환 금지 |
| Kronos 기타 | GB Bug·Mongo·Buddy/Delirium | 실물 반환·재흡수 금지, Minisaac 충원, 층별 선택 유지/재구성 |

## 친구 상자 임시 배율 추가 검사

게임 실행 명령: `conch_test kronos box_of_friends` (기존 전체 검사에도 포함).
바비·가디언 엔젤·파스카 양초·동전 주머니·몽고 아기를 실제로 획득해 흡수시킨다.

| 검사 | 기대 결과 | 검증 상태 |
| --- | --- | --- |
| 기본 흡수→친구 상자 | 흡수 공격력 +10→+20, 바비 연사 +2→+4, 가디언 이동속도 +0.3→+0.6 | 게임 검사 작성, 실행 대기 |
| 이미 받은 변환 아이템 | Dollar 1개 유지, 사용 전 코인 유지 | 게임 검사 작성, 실행 대기 |
| 파스카 누적 후 상자 사용 | 기존 +0.03의 적용값만 +0.06 | 게임 검사 작성, 실행 대기 |
| 상자 활성 중 실제 클리어 보상 | 누적 원본 +0.06, 그 방의 적용값 +0.12 | 게임 검사 작성, 실행 대기 |
| 다른 방으로 이동→원래 방 재진입 | 공격력·연사·이동속도 모두 원래 흡수분으로 복귀, 배율 부활 없음 | 게임 검사 작성, 실행 대기 |
| 몽고 추가 미니 아이작 | 보유 효과 1→2→1, 관계없는 미니 아이작 보존 | 게임 검사 작성, 실행 대기 |
| 다시 상자 사용→크로노스 제거 | 원본 펫만 각각 1개 반환, 임시 추가 공격력·추가 몽고 회수, Dollar 회수 | 게임 검사 작성, 실행 대기 |
| 같은 방에서 반복 사용 | 사용마다 원본 효과 1세트 추가, 흡수 원장·지급 개수 불변 | 오프라인 생산 코드 검사 통과 |
| 종료 콜백 순서 | StatsAPI 기본 우선순위 디스크 기록 전에 임시 공격력 회수 | 오프라인 공급자 모형 검사 통과 |
| 오래된 임시 스탯·우선순위 API 부재 | 시작 시 원본 흡수 수로 스탯 보정, 일반 콜백 대체 경로 유지 | 오프라인 생산 코드 검사 통과 |
| Monster Manual·Lilith·Pretty Fly + 상자 | 상자만 만료, 원본 임시/영구 흡수는 보존; Manual은 새 층에서만 만료 | 오프라인 생산 코드 검사 통과 |
| 실제 게임 종료→Continue | 두 배 효과 미복원, 원본 흡수·누적량 보존, 추가 소환 미잔류 | 별도 실행 대기 — 오프라인 검사로 대체 불가 |

`tests/test_kronos_room_effects.py`는 위 상태 전이와 영구 누적 방지를 실제 아이템 Lua 코드로 검사한다.
엔진·StatsAPI만 모형으로 대체하므로 실제 Continue, 엔티티 직렬화, 렌더링의 통과 증거는 아니다.

## 판정 한계

- 이 확장본은 아직 게임에서 실행하지 않았다. 아래 각 행은 구현된 테스트의 목표이며, 실행 통과 표시가 아니다.
- 보상으로 지급한 바닐라 아이템의 소유권·개수·회수는 확인한다. 해당 바닐라 아이템 자체의 모든 엔진 기능을 재검증하지는 않는다.
- Buddy/Delirium의 선택 기록·층 전환, Prism 분열 발생, 아군 소환의 개수·진영 검사는 구현됐다. 무작위로 뽑힌 모든 능력의 개별 발동, 모든 방향/무기별 Prism 분열 수, 소환 아군의 모든 AI 공격까지 통과한 것으로 해석하지 않는다.
- 확률 100% 중첩과 0% 조건을 우선 검사한다. Twins의 24회 방 진입에서 두 결과를 관찰해도 50% 분포를 증명하지 않는다. 한 결과만 나오면 SKIP/재검 대상이다.
- Monster Manual이 제외된 펫만 뽑으면 해당 시나리오는 SKIP 후 재검한다. 정상 펫이 나왔는데 흡수가 안 되면 FAIL이다.
- 문자·범위 이펙트의 가시성, 게임 종료 후 실제 Continue, 협동 플레이, 모든 무기 계열별 교차 조합은 별도 실행이 필요하다.
- 영원한 불꽃의 영구 보상과 마검 전부 진화는 확정된 사용자 의도대로 게임 코드를 수정했다. 기존 검사 기대값을 유지하고 실제 게임에서 다시 확인한다.
- 60초 성장 정지·정기 동전 지급은 테스트 전용 시계로 1799/1800/1801틱을 가속 검사한다. 실제 업데이트·동전 생성은 그대로 관찰한다. 실제 시간 경과·Continue 검증은 별도다.
- 배열·다이스 검사 4개와 안전한 재시작 묶기의 상세 표는 [아이템 검사 문서](item_testing.md#대기재시작배열-검사-개선)를 참조한다. 테스트 결과 로그는 MCM 디버그 설정과 무관하게 남는다.

## 등록 시너지 전체 144개

크로노스 개별 펫 행은 흡수/기본 +2/마지막 제거 검사를 공통으로 포함한다.
설명은 기대 동작의 출처이며, 세부 검증 범위와 미검증 부분은 위 표와 한계를 따른다.

| 아이템 | 시너지 키 | 설명상의 기대 동작 | 연결된 검사 명령 |
| --- | --- | --- | --- |
| 살아있는 눈 (`LIVE_EYE`) | `rock_bottom` | 데미지 배수가 최대치인 x3.0으로 고정됩니다. (눈물이 아닌 공격이어도 동일) | `conch_test live_eye weapon_and_rock_bottom` |
| 진 (`DRAGON`) | `dragon` | 전기 구체가 태풍으로 변합니다 / 태풍이 멈추면 해당 위치에 소용돌이가 생성되어 2초간 적을 끌어당깁니다 / 소용돌이가 사라질 때, 내 데미지의 25배의 폭발이 발생합니다 / 중첩시 데미지 25% 증가 | `conch_test dragon vortex_damage` |
| 크로노스 (`KRONOS`) | `twisted_pair` | 37.5% 데미지의 공격을 2개 추가합니다. | `conch_test kronos twisted_pair` |
| 크로노스 (`KRONOS`) | `succubus` | 내 주변으로 오라가 고정됩니다. | `conch_test kronos succubus` |
| 크로노스 (`KRONOS`) | `incubus` | 75% 데미지의 공격을 1개 추가합니다. | `conch_test kronos incubus` |
| 크로노스 (`KRONOS`) | `seraphim` | 공중, 지형관통 효과를 얻습니다. / {c:SACRED_HEART} 신성한 심장을 획득합니다. (최초 1회) | `conch_test kronos seraphim` |
| 크로노스 (`KRONOS`) | `robo_baby` | {c:TECHNOLOGY} 테크를 얻습니다. | `conch_test kronos robo_baby` |
| 크로노스 (`KRONOS`) | `robo_baby_2` | {c:TECHNOLOGY_2} 테크 2를 얻습니다. | `conch_test kronos robo_baby_2` |
| 크로노스 (`KRONOS`) | `blue_babys_only_friend` | {c:LUDOVICO_TECHNIQUE} 루도비코를 얻습니다. (최초 1회) | `conch_test kronos blue_babys_only_friend` |
| 크로노스 (`KRONOS`) | `lil_brimstone` | {c:BRIMSTONE} 혈사를 얻습니다. | `conch_test kronos lil_brimstone` |
| 크로노스 (`KRONOS`) | `bobs_brain` | {c:IPECAC} 구토제를 얻습니다. (최초 1회) | `conch_test kronos bobs_brain` |
| 크로노스 (`KRONOS`) | `lil_monstro` | {c:MONSTROS_LUNG} 몬스트로의 폐를 얻습니다. (최초 1회) | `conch_test kronos lil_monstro` |
| 크로노스 (`KRONOS`) | `lil_haunt` | 모든 공격에 공포 효과를 부여합니다. | `conch_test kronos lil_haunt` |
| 크로노스 (`KRONOS`) | `blood_puppy` | {c:GIMPY} 김피를 얻습니다. (최초 1회) | `conch_test kronos blood_puppy` |
| 크로노스 (`KRONOS`) | `angelic_prism` | 공격이 4갈래로 갈라져 나갑니다. | `conch_test kronos angelic_prism` |
| 크로노스 (`KRONOS`) | `bot_fly` | {c:LOST_CONTACT} 잃어버린 렌즈를 얻습니다. (최초 1회) | `conch_test kronos bot_fly` |
| 크로노스 (`KRONOS`) | `freezer_baby` | {c:URANUS} 천왕성을 얻습니다. (최초 1회) | `conch_test kronos freezer_baby` |
| 크로노스 (`KRONOS`) | `lil_abaddon` | {c:MAW_OF_THE_VOID} 공허의 구렁텅이를 얻습니다. (최초 1회) | `conch_test kronos lil_abaddon` |
| 크로노스 (`KRONOS`) | `multidimensional_baby` | {c:20_20} 20/20을 얻습니다. | `conch_test kronos multidimensional_baby` |
| 크로노스 (`KRONOS`) | `harlequin_baby` | {c:THE_WIZ} 법사를 얻습니다. | `conch_test kronos harlequin_baby` |
| 크로노스 (`KRONOS`) | `brother_bobby` |  고정연사 +2를 얻습니다. | `conch_test kronos brother_bobby` |
| 크로노스 (`KRONOS`) | `demon_baby` | {c:MARKED} 표식을 얻습니다. (최초 1회) | `conch_test kronos demon_baby` |
| 크로노스 (`KRONOS`) | `little_gish` | 모든 공격에 느림 효과를 부여합니다. | `conch_test kronos little_gish` |
| 크로노스 (`KRONOS`) | `lil_loki` | {c:LOKIS_HORNS} 로키의 뿔을 얻습니다. | `conch_test kronos lil_loki` |
| 크로노스 (`KRONOS`) | `ghost_baby` | {c:CONTINUUM} 연속체를 얻습니다. | `conch_test kronos ghost_baby` |
| 크로노스 (`KRONOS`) | `rotten_baby` | 공격이 적에게 피해를 주면 50% 확률로 아군 파리를 소환합니다. ({c:7_SEALS} 7개의 도장과 합산, 최대 100%) / 현재 아군 파리 소환 확률: %KRONOS_FLY% | `conch_test kronos rotten_baby` |
| 크로노스 (`KRONOS`) | `little_steven` | 유도 효과를 얻습니다. | `conch_test kronos little_steven` |
| 크로노스 (`KRONOS`) | `rainbow_baby` | {c:FRUIT_CAKE} 과일 케이크를 얻습니다. (최초 1회) | `conch_test kronos rainbow_baby` |
| 크로노스 (`KRONOS`) | `guardian_angel` | 이동 속도 +0.3을 얻습니다. | `conch_test kronos guardian_angel` |
| 크로노스 (`KRONOS`) | `censer` | 향로의 오라 효과가 플레이어 위치에 고정됩니다. | `conch_test kronos censer` |
| 크로노스 (`KRONOS`) | `leech` | {c:CHARM_VAMPIRE} 흡혈귀의 부적을 얻습니다. (최초 1회) | `conch_test kronos leech` |
| 크로노스 (`KRONOS`) | `bomb_bag` | {c:PYRO} 파이로를 얻습니다. (최초 1회) | `conch_test kronos bomb_bag` |
| 크로노스 (`KRONOS`) | `dark_bum` | {c:MITRE} 주교관을 얻습니다. (최초 1회) | `conch_test kronos dark_bum` |
| 크로노스 (`KRONOS`) | `key_bum` | {c:SKELETON_KEY} 해골 열쇠를 얻습니다. (최초 1회) | `conch_test kronos key_bum` |
| 크로노스 (`KRONOS`) | `abel` | {c:MY_REFLECTION} 거울을 얻습니다. (최초 1회) | `conch_test kronos abel` |
| 크로노스 (`KRONOS`) | `star_of_bethlehem` | 베들레헴의 별 오라가 플레이어 위치에 고정됩니다. / {c:COMPASS} 나침반을 얻습니다. (최초 1회) | `conch_test kronos star_of_bethlehem` |
| 크로노스 (`KRONOS`) | `farting_baby` | {c:JELLY_BELLY} 젤리 배를 얻습니다. (최초 1회) | `conch_test kronos farting_baby` |
| 크로노스 (`KRONOS`) | `samsons_chains` | {c:THUNDER_THIGHS} 천둥 허벅지를 얻습니다. (최초 1회) | `conch_test kronos samsons_chains` |
| 크로노스 (`KRONOS`) | `finger` | {c:TRACTOR_BEAM} 트랙터 빔을 얻습니다. (최초 1회) | `conch_test kronos finger` |
| 크로노스 (`KRONOS`) | `little_chad` | {c:CANDY_HEART} 캔디 하트를 얻습니다. (최초 1회) | `conch_test kronos little_chad` |
| 크로노스 (`KRONOS`) | `sack_of_pennies` | {c:DOLLAR} 달러를 얻습니다. (최초 1회) | `conch_test kronos sack_of_pennies` |
| 크로노스 (`KRONOS`) | `sack_of_sacks` | {c:SACK_HEAD} 자루 머리를 얻습니다. (최초 1회) | `conch_test kronos sack_of_sacks` |
| 크로노스 (`KRONOS`) | `charged_baby` | {c:9_VOLT} 9볼트를 얻습니다. (최초 1회) | `conch_test kronos charged_baby` |
| 크로노스 (`KRONOS`) | `yo_listen` | {c:XRAY_VISION} 엑스레이 투시를 얻습니다. (최초 1회) | `conch_test kronos yo_listen` |
| 크로노스 (`KRONOS`) | `daddy_longlegs` | 공격이 적에게 피해를 주면 10% 확률로 다리가 내려찍어 주변 적에게 공격력 x2의 피해를 줍니다. (흡수할 때마다 누적) / 현재 내려찍기 확률: %KRONOS_STOMP% | `conch_test kronos daddy_longlegs` |
| 크로노스 (`KRONOS`) | `sister_maggy` | {c:CRICKETS_HEAD} 크리켓의 머리를 얻습니다. (최초 1회) | `conch_test kronos sister_maggy` |
| 크로노스 (`KRONOS`) | `little_chubby` | {c:MARS} 화성을 얻습니다. (최초 1회) | `conch_test kronos little_chubby` |
| 크로노스 (`KRONOS`) | `big_chubby` | {c:MARS} 화성을 얻습니다. (최초 1회) / 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos big_chubby` |
| 크로노스 (`KRONOS`) | `peeper` | {c:MOMS_EYE} 엄마의 눈알을 얻습니다. (최초 1회) | `conch_test kronos peeper` |
| 크로노스 (`KRONOS`) | `bbf` | {c:FIRE_MIND} 불타는 마음을 얻습니다. (최초 1회) | `conch_test kronos bbf` |
| 크로노스 (`KRONOS`) | `fates_reward` | {c:20_20} 시력 2.0을 얻습니다. (최초 1회) | `conch_test kronos fates_reward` |
| 크로노스 (`KRONOS`) | `lil_gurdy` | {c:CHOCOLATE_MILK} 초콜릿 우유를 얻습니다. (최초 1회) | `conch_test kronos lil_gurdy` |
| 크로노스 (`KRONOS`) | `bumbo` | {c:PIGGY_BANK} 돼지 저금통을 얻습니다. (최초 1회) | `conch_test kronos bumbo` |
| 크로노스 (`KRONOS`) | `spider_mod` | {c:SPIDER_BITE} 거미물림을 얻습니다. (최초 1회) | `conch_test kronos spider_mod` |
| 크로노스 (`KRONOS`) | `depression` | {c:HOLY_LIGHT} 신성한 빛을 얻습니다. (최초 1회) | `conch_test kronos depression` |
| 크로노스 (`KRONOS`) | `king_baby` | {c:MAGIC_MUSHROOM} 마법의 버섯을 얻습니다. (최초 1회) | `conch_test kronos king_baby` |
| 크로노스 (`KRONOS`) | `acid_baby` | {c:PHD} 박사학위를 얻습니다. (최초 1회) | `conch_test kronos acid_baby` |
| 크로노스 (`KRONOS`) | `jaw_bone` | {c:COMPOUND_FRACTURE} 복합 골절을 얻습니다. (최초 1회) | `conch_test kronos jaw_bone` |
| 크로노스 (`KRONOS`) | `boiled_baby` | {c:EYE_SORE} 흉물을 얻습니다. (최초 1회) | `conch_test kronos boiled_baby` |
| 크로노스 (`KRONOS`) | `lil_dumpy` | {c:JELLY_BELLY} 젤리 배를 얻습니다. (최초 1회) | `conch_test kronos lil_dumpy` |
| 크로노스 (`KRONOS`) | `fruity_plum` | {c:KIDNEY_STONE} 신장 결석을 얻습니다. (최초 1회) | `conch_test kronos fruity_plum` |
| 크로노스 (`KRONOS`) | `7_seals` | 공격이 적에게 피해를 주면 50% 확률로 아군 파리를 소환합니다. ({c:ROTTEN_BABY} 썩은 아기와 합산, 최대 100%) / 현재 아군 파리 소환 확률: %KRONOS_FLY% | `conch_test kronos 7_seals` |
| 크로노스 (`KRONOS`) | `juicy_sack` | 공격이 적에게 피해를 주면 50% 확률로 아군 거미를 소환합니다. ({c:SISSY_LONGLEGS} 눈나 거미와 합산, 최대 100%) / 현재 아군 거미 소환 확률: %KRONOS_SPIDER% | `conch_test kronos juicy_sack` |
| 크로노스 (`KRONOS`) | `sissy_longlegs` | 공격이 적에게 피해를 주면 50% 확률로 아군 거미를 소환합니다. ({c:JUICY_SACK} 축축한 알집과 합산, 최대 100%) / 현재 아군 거미 소환 확률: %KRONOS_SPIDER% | `conch_test kronos sissy_longlegs` |
| 크로노스 (`KRONOS`) | `intruder` | 모든 공격에 느림 효과를 부여합니다. | `conch_test kronos intruder` |
| 크로노스 (`KRONOS`) | `worm_friend` | 모든 공격에 느림 효과를 부여합니다. | `conch_test kronos worm_friend` |
| 크로노스 (`KRONOS`) | `halo_of_flies` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos halo_of_flies` |
| 크로노스 (`KRONOS`) | `distant_admiration` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos distant_admiration` |
| 크로노스 (`KRONOS`) | `cube_of_meat` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos cube_of_meat` |
| 크로노스 (`KRONOS`) | `forever_alone` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos forever_alone` |
| 크로노스 (`KRONOS`) | `sacrificial_dagger` | 적의 탄환에 맞을 때 2% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos sacrificial_dagger` |
| 크로노스 (`KRONOS`) | `guppys_hairball` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos guppys_hairball` |
| 크로노스 (`KRONOS`) | `guillotine` | 공격력 +1, 연사 +0.5 (흡수할 때마다 누적) / 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos guillotine` |
| 크로노스 (`KRONOS`) | `ball_of_bandages` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos ball_of_bandages` |
| 크로노스 (`KRONOS`) | `smart_fly` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos smart_fly` |
| 크로노스 (`KRONOS`) | `best_bud` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos best_bud` |
| 크로노스 (`KRONOS`) | `big_fan` | 적의 탄환에 맞을 때 2% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos big_fan` |
| 크로노스 (`KRONOS`) | `punching_bag` | 적의 탄환에 맞을 때 2% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos punching_bag` |
| 크로노스 (`KRONOS`) | `sworn_protector` | 적의 탄환에 맞을 때 5% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos sworn_protector` |
| 크로노스 (`KRONOS`) | `friend_zone` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos friend_zone` |
| 크로노스 (`KRONOS`) | `lost_fly` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos lost_fly` |
| 크로노스 (`KRONOS`) | `hushy` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos hushy` |
| 크로노스 (`KRONOS`) | `moms_razor` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) /  공격이 적에게 피해를 주면 10% 확률로 출혈시킵니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% / 현재 출혈 확률: %KRONOS_BLEED% | `conch_test kronos moms_razor` |
| 크로노스 (`KRONOS`) | `angry_fly` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos angry_fly` |
| 크로노스 (`KRONOS`) | `leprosy` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos leprosy` |
| 크로노스 (`KRONOS`) | `slipped_rib` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos slipped_rib` |
| 크로노스 (`KRONOS`) | `pointy_rib` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos pointy_rib` |
| 크로노스 (`KRONOS`) | `psy_fly` | 적의 탄환에 맞을 때 5% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos psy_fly` |
| 크로노스 (`KRONOS`) | `tinytoma` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos tinytoma` |
| 크로노스 (`KRONOS`) | `headless_baby` | {c:AQUARIUS} 물병자리를 얻습니다. (최초 1회) | `conch_test kronos headless_baby` |
| 크로노스 (`KRONOS`) | `cains_other_eye` | {c:RUBBER_CEMENT} 고무 접착제를 얻습니다. (최초 1회) | `conch_test kronos cains_other_eye` |
| 크로노스 (`KRONOS`) | `papa_fly` | {c:HIVE_MIND} 군체의식을 얻습니다. (최초 1회) | `conch_test kronos papa_fly` |
| 크로노스 (`KRONOS`) | `shade` | {c:LUSTY_BLOOD} 욕망의 피를 얻습니다. (최초 1회) | `conch_test kronos shade` |
| 크로노스 (`KRONOS`) | `obsessed_fan` | 적의 탄환에 맞을 때 1% 확률로 피해를 무시합니다. (흡수할 때마다 누적) / 현재 탄환 무시 확률: %KRONOS_BLOCK% | `conch_test kronos obsessed_fan` |
| 크로노스 (`KRONOS`) | `gemini` | 접촉한 적에게 초당 6의 피해를 줍니다. (흡수할 때마다 누적) | `conch_test kronos gemini` |
| 크로노스 (`KRONOS`) | `cube_baby` |  공격이 적에게 피해를 주면 10% 확률로 적을 2초간 얼려 멈춥니다. (흡수할 때마다 누적) / 현재 빙결 확률: %KRONOS_FREEZE% | `conch_test kronos cube_baby` |
| 크로노스 (`KRONOS`) | `lil_spewer` | 공격이 적에게 피해를 주면 25% 확률로 적 위치에 빨간 장판이 생깁니다. (흡수할 때마다 누적) / 현재 장판 생성 확률: %KRONOS_CREEP% | `conch_test kronos lil_spewer` |
| 크로노스 (`KRONOS`) | `gb_bug` | 흡수 시 지금까지 흡수한 다른 패밀리어 중 무작위로 절반을 되돌려줍니다. / 되돌아온 패밀리어는 다시 흡수되지 않습니다. | `conch_test kronos gb_bug` |
| 크로노스 (`KRONOS`) | `bum_friend` | 방 클리어 시 10% 확률로 랜덤 픽업을 드랍합니다. (흡수할 때마다 누적) / 현재 픽업 드랍 확률: %KRONOS_PICKUP_DROP% | `conch_test kronos bum_friend` |
| 크로노스 (`KRONOS`) | `lil_chest` |  방 클리어 시 10% 확률로 상자를 드랍합니다. (흡수할 때마다 누적) / 현재 상자 드랍 확률: %KRONOS_CHEST_DROP% | `conch_test kronos lil_chest` |
| 크로노스 (`KRONOS`) | `relic` |  방 6개 클리어마다 소울하트를 드랍합니다. (흡수할 때마다 1개씩 추가) | `conch_test kronos relic` |
| 크로노스 (`KRONOS`) | `mystery_sack` | 방 6개 클리어마다 랜덤 픽업을 드랍합니다. (흡수할 때마다 1개씩 추가) | `conch_test kronos mystery_sack` |
| 크로노스 (`KRONOS`) | `rune_bag` |  방 7개 클리어마다 룬을 드랍합니다. (흡수할 때마다 1개씩 추가) | `conch_test kronos rune_bag` |
| 크로노스 (`KRONOS`) | `paschal_candle` |  방 클리어 시마다 연사 +0.03 (흡수할 때마다 누적) | `conch_test kronos paschal_candle` |
| 크로노스 (`KRONOS`) | `holy_water` | 피격 시 캐릭터 위치에 성수 장판이 생깁니다. (흡수할 때마다 1개씩 추가, 최대 4개) | `conch_test kronos holy_water` |
| 크로노스 (`KRONOS`) | `dry_baby` | 피격 시 25% 확률로 {c:NECRONOMICON} 네크로노미콘이 발동합니다. (흡수할 때마다 누적) / 현재 네크로노미콘 발동 확률: %KRONOS_NECRONOMICON% | `conch_test kronos dry_baby` |
| 크로노스 (`KRONOS`) | `milk` |  스테이지에서 처음 피격 시 그 스테이지 동안 연사 +1 (흡수할 때마다 누적) | `conch_test kronos milk` |
| 크로노스 (`KRONOS`) | `bird_cage` | 피격 시 가장 가까운 적에게 45의 피해를 줍니다. (흡수할 때마다 누적) | `conch_test kronos bird_cage` |
| 크로노스 (`KRONOS`) | `mystery_egg` |  피격 시 매혹된 아군 파리를 소환합니다. (흡수할 때마다 1마리씩 추가, 최대 5마리) | `conch_test kronos mystery_egg` |
| 크로노스 (`KRONOS`) | `my_shadow` |  피격 시 검은색 아군 애벌레를 소환합니다. (흡수할 때마다 1마리씩 추가, 최대 3마리) | `conch_test kronos my_shadow` |
| 크로노스 (`KRONOS`) | `hallowed_ground` | 피격 시 근처에 하얀 똥을 설치합니다. | `conch_test kronos hallowed_ground` |
| 크로노스 (`KRONOS`) | `lost_soul` |  피격 없이 스테이지를 넘어가면 이터널하트를 드랍합니다. (흡수할 때마다 1개씩 추가) | `conch_test kronos lost_soul` |
| 크로노스 (`KRONOS`) | `bloodshot_eye` | 피눈물 눈알이 플레이어 위치에 고정됩니다. | `conch_test kronos bloodshot_eye` |
| 크로노스 (`KRONOS`) | `mongo_baby` | 방에 들어갈 때마다 미니 아이작을 흡수한 수만큼 채워줍니다. | `conch_test kronos mongo_baby` |
| 크로노스 (`KRONOS`) | `buddy_in_a_box` | 스테이지마다 다른 패밀리어 하나의 흡수 효과를 무작위로 얻습니다. (흡수할 때마다 1개씩 추가) | `conch_test kronos buddy_in_a_box` |
| 크로노스 (`KRONOS`) | `lil_delirium` | 스테이지마다 다른 패밀리어 하나의 흡수 효과를 무작위로 얻습니다. (흡수할 때마다 1개씩 추가) | `conch_test kronos lil_delirium` |
| 크로노스 (`KRONOS`) | `box_of_friends` | 사용 시 그 방에서 흡수 공격력과 고유능력이 2배가 됩니다. 방을 나가거나 이어하기 시 해제되며 변환 아이템은 추가 지급하지 않습니다. | `conch_test kronos box_of_friends` |
| 크로노스 (`KRONOS`) | `monster_manual` | 크로노스 획득 전후에 소환한 패밀리어를 흡수해 그 스테이지 동안 데미지 +2와 고유 효과 또는 변환 아이템을 얻습니다. 방 이동으로 같은 흡수 보상을 다시 얻지 않습니다. | `conch_test kronos manual_before` |
| 크로노스 (`KRONOS`) | `sacrificial_altar` | 사용 시 흡수한 패밀리어를 최대 2마리 제물로 바쳐 악마방 아이템을 생성합니다. | `conch_test kronos sacrificial_altar` |
| 크로노스 (`KRONOS`) | `trinket_the_twins` | 방 입장 시 50% 확률로 그 방에서 흡수한 패밀리어 하나의 효과가 2배가 됩니다. | `conch_test kronos trinket_the_twins` |
| 크로노스 (`KRONOS`) | `1up` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos 1up` |
| 크로노스 (`KRONOS`) | `isaacs_heart` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos isaacs_heart` |
| 크로노스 (`KRONOS`) | `dead_cat` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos dead_cat` |
| 크로노스 (`KRONOS`) | `key_piece_1` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos key_piece_1` |
| 크로노스 (`KRONOS`) | `key_piece_2` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos key_piece_2` |
| 크로노스 (`KRONOS`) | `knife_piece_1` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos knife_piece_1` |
| 크로노스 (`KRONOS`) | `knife_piece_2` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos knife_piece_2` |
| 크로노스 (`KRONOS`) | `damocles_passive` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos damocles_passive` |
| 크로노스 (`KRONOS`) | `straw_man` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos straw_man` |
| 크로노스 (`KRONOS`) | `blood_oath` | {own:KRONOS} 크로노스에 흡수되지 않습니다. | `conch_test kronos blood_oath` |
| 감정 평가서 (`APPRAISAL_CERTIFICATE`) | `atropos` | 각 방에서 장신구 하나를 획득하면 그 방에 남은 장신구만 사라집니다. / 획득한 장신구는 흡수되며, 다른 방에서도 하나씩 고를 수 있습니다. | `conch_test appraisal detail` |
| 다용도 벨트 (`UTILITY_BELT`) | `book_of_virtues` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt book_of_virtues` |
| 다용도 벨트 (`UTILITY_BELT`) | `d_infinity` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt d_infinity` |
| 다용도 벨트 (`UTILITY_BELT`) | `blank_card` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt blank_card` |
| 다용도 벨트 (`UTILITY_BELT`) | `placebo` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt placebo` |
| 다용도 벨트 (`UTILITY_BELT`) | `clear_rune` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt clear_rune` |
| 다용도 벨트 (`UTILITY_BELT`) | `glowing_hour_glass` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt glowing_hour_glass` |
| 다용도 벨트 (`UTILITY_BELT`) | `jar_of_wisps` |  해당 액티브는 포켓 슬롯으로 이동되지 않습니다 | `conch_test utility_belt jar_of_wisps` |
| SOFLAM (`SOFLAM`) | `mr_mega` | 폭발 범위가 1.5배가 됩니다 (1회) / 미사일 데미지가 Mr. Mega 개수만큼 2배씩 중첩됩니다 | `conch_test soflam mr_mega_and_multishot` |
| 반올림 (`ROUND`) | `ceil` | 올림이 먼저 적용되므로 반올림은 효과가 없습니다. | `conch_test round ceil` |
| 내림 (`FLOOR`) | `ceil` | 올림이 먼저 적용되고, 기본 스탯 보장만 추가로 적용됩니다. | `conch_test floor ceil` |
| 내림 (`FLOOR`) | `round` | 반올림이 먼저 적용되고, 기본 스탯 보장만 추가로 적용됩니다. | `conch_test floor round` |
| 시간 = 돈 (`TIME_MONEY`) | `bffs` | 동전 드랍 비율이 10%로 증가합니다. | `conch_test time_money bffs_period_and_penalty` |
| 아트로포스 (`ATROPOS`) | `death_certificate` | 사망 증명서 공간의 첫 방 왼쪽에 원래 방으로 돌아가는 문이 열립니다. / 아이템 하나를 획득하면 해당 방에 남은 아이템이 모두 사라지지만, 자동으로 원래 방으로 돌아가지는 않습니다. | `conch_test atropos death_certificate` |

## 그 밖의 추가 시나리오 명령

| 아이템 | 명령 |
| --- | --- |
| `B_MINUS` | `conch_test b_minus floor_evolution_normal` |
| `B_MINUS` | `conch_test b_minus floor_evolution_golden` |
| `F_MINUS` | `conch_test f_minus floor_evolution_normal` |
| `F_MINUS` | `conch_test f_minus floor_evolution_golden` |
| `C_MINUS` | `conch_test c_minus floor_evolution_normal` |
| `C_MINUS` | `conch_test c_minus floor_evolution_golden` |
| `A_MINUS` | `conch_test a_minus hit_demotes` |
| `TIME_POWER` | `conch_test time_power hit_pause_resume` |
| `TIME_LUCK` | `conch_test time_luck hit_pause_resume` |
| `TIME_TEAR` | `conch_test time_tear hit_pause_resume` |
| `TWO_FACED_PENNY` | `conch_test two_faced_penny clean_and_hit_floors` |
| `TIME_POWER` | `conch_test time_power moms_box` |
| `F_MINUS` | `conch_test f_minus moms_box` |
| `TIME_LUCK` | `conch_test time_luck moms_box` |
| `TIME_TEAR` | `conch_test time_tear moms_box` |
| `B_MINUS` | `conch_test b_minus moms_box` |
| `C_MINUS` | `conch_test c_minus moms_box` |
| `ICE_BREATH` | `conch_test ice_breath status_conditions` |
| `FIRE_BREATH` | `conch_test fire_breath status_conditions` |
| `KRONOS` | `conch_test kronos manual_after` |
