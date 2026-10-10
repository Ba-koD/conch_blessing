# 강화 연출 미리보기

`item-upgrade-player.html`을 직접 열면 재생됩니다. 서버와 인터넷은 필요하지 않습니다.
아이콘으로 항목을 선택하고, **전체 / 인게임 적용 / 보류**로 목록을 나눌 수 있습니다.
한글 검색, 시간 이동, 재생·일시 정지, 반복 및 효과음 설정을 지원합니다.

HTML은 연출 시안입니다. 게임에서 사용하는 Lua 렌더러의 결과는 아래 명령으로 확인합니다.
보류 시안은 HTML에서만 재생되며, 게임에서는 기존 기본 강화 연출을 유지합니다.
HTML의 크로노스 보유 펫 선택은 예시 목록이며 실제 게임의 인벤토리와 연결되지 않습니다.

| 게임 콘솔 | 동작 |
| --- | --- |
| `conch_morph` | 31종 강화 연출 보기 |
| `conch_morph liveeye` | 살아있는 눈 선택 (보류: 현재 기본 연출) |
| `conch_morph soflam` | SOFLAM 미사일 연출 |
| `conch_morph time_tear` | 시간 = 연사 연출 (`timetear`도 가능) |
| `conch_morph list` | 항목 및 적용 상태 목록 |
| `conch_morph stop` | 종료 및 입력 복원 |

- **R**: 현재 연출 처음부터 재생
- **← / ↑**: 이전 아이템, **→ / ↓**: 다음 아이템
- **Backspace**: 종료
- 화면 아래에 현재 항목, 적용 여부, 이전·다음 아이콘을 표시합니다.
- 아이템 지급, 런 재시작 및 전투 효과 생성 없이 스프라이트만 표시합니다. 게임 진행 자체를 정지시키지는 않으므로 빈 방에서 보는 것이 편합니다.
- 방 이동·게임 종료·새 게임 시작 시 종료하며, `conch_test` 실행 중에는 열리지 않습니다.
- 새 ANM2를 처음 적용하거나 수정한 뒤에는 게임을 완전히 재실행해야 합니다.

현재 적용 대상은 공허의 단검, 진, 돈 = 연사, 서리의 숨결, 화염의 숨결, SOFLAM,
시간 = 돈 패밀리어와 9종 장신구(시간 = 힘·연사·행운, F−·C−·B−·A−, 아트로포스, 천사의 왕관)입니다.
비 연출의 바닥 침수 표시는 REPENTOGON의 바닥/벽 사이 그리기 콜백이 있는 경우에만 표시합니다.
콜백이 없는 게임에서는 비와 물결을 표시하며 실제 방 지형은 바꾸지 않습니다.

## 관리 및 검증

- 적용 목록: `scripts/upgrade_visual_catalog.lua`
- HTML 상태 동기화: `python sync_upgrade_preview.py` (`--check`로 일치 검사)
- 런타임 보조 이미지/ANM2 재생성: `python generate_upgrade_visual_assets.py`
- 오프라인 검사: `python -m unittest discover -s tests -p test_morph_viewer.py -v`
- HTML 동작·Canvas 검사: `node tests/check_upgrade_preview.cjs` (`@napi-rs/canvas` 필요, 저장소 루트에서 실행; 브라우저 레이아웃 검사와는 별개)
- 실제 게임 검증: 각 연출, 재시작·이동 키, 일시 정지, 방 이동, 실제 Magic Conch 강화 전환을 확인하고 `log.txt`의 `[ConchMorph]` 및 리소스 오류 확인

오프라인 Lua 더블·Canvas 검사는 실제 엔진 화면 확인을 대신하지 않습니다.
이 폴더는 Workshop 패키지에 포함되지 않습니다. main 푸시는 위키 갱신 알림을 보낼 수 있지만,
Workshop 업로드는 별도 수동 워크플로로만 실행됩니다.
