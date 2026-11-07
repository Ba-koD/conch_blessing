# Aseprite 네 종 재작업

2026-10-24. 사용자가 Aseprite 설치와 네 종의 재작업을 요청한 검토본이다. 현재 배포된 원본 PNG와 나머지 아이템은 변경하지 않았다.

| 아이템 | 편집 원본 | PNG | 구성 |
| --- | --- | --- | --- |
| 봉인된 마검 | [sealed_demon_sword.aseprite](sealed_demon_sword.aseprite) | [PNG](sealed_demon_sword.png) | 사선으로 길어진 어두운 검신·뿔 모양 가드·두 봉인띠·붉은 밀랍 |
| 티르핑 | [tyrfing.aseprite](tyrfing.aseprite) | [PNG](tyrfing.png) | 칼끝이 좁아지는 긴 사선 검신·역날·붉은 균열·가드의 붉은 눈 |
| 경구형 스테로이드 | [oral_steroids.aseprite](oral_steroids.aseprite) | [PNG](oral_steroids.png) | 승인된 약 봉지 질감 유지·방향과 형태를 나눈 알약 아홉 개 |
| 적사단지 | [severed_oath.aseprite](severed_oath.aseprite) | [PNG](severed_oath.png) | 시계 방향으로 기울인 구도·두꺼운 날과 고리·열린 날 사이의 붉은 실 |

[원본/수정본 비교](comparison.png)는 실제 내보낸 PNG의 1배와 4배 최근접 확대다.

공식 소스 `v1.3.18.6`를 Windows에서 빌드한 Aseprite로 작성했다. 32×32 RGBA 캔버스에 Lua API로 픽셀을 배치하고, Aseprite의 레이어와 저장·PNG 내보내기를 사용했다. 확대 그림을 축소한 단계는 없다. 각 프로젝트의 맨 아래에는 숨김·잠금 상태의 원본 참고 레이어가 있다. 약 봉지는 원본 네이티브 알파 영역에서 시작해 외곽·주름·내용물을 다시 정리했다.

후속 사용자 요청에 따라 [Blizzard 공식 서리한 사진](https://gear.blizzard.com/products/wowcnv0028-frostmourne-sword-foam-replica)의 테이퍼·역날·뿔형 가드와 [Matt W.의 Erkimos 제작 기록](https://uzarran.artstation.com/projects/5XdJqJ)의 붉은 결정 표현을 조사했다. 사진의 해골·장식이나 고유 형상을 복제하지 않고, 어두운 검신과 제한된 붉은 초점으로 위협적인 인상을 주는 구성 원리를 참고했다. 참조 이미지는 저장소 밖에 보관했다. 블리스터 포장은 사용자가 더 거친 인상의 약 봉지를 선호하여 교체했다. 후속 비율 수정에서는 칼끝을 오른쪽 위, 손잡이를 왼쪽 아래에 놓아 검신이 전체 축 길이의 약 3/4을 차지하도록 직접 다시 그렸다. 약 봉지의 외곽·지퍼·주름 레이어는 그대로 두고 내용물만 아홉 알로 늘렸다. 가위는 금속 면을 두껍게 하고 열린 날의 중심축을 시계 방향으로 기울였으며, 고리의 빈 공간과 붉은 실을 보존했다.

편집은 `.aseprite`를 열어 진행하고 PNG를 다시 내보낸다. `author.lua`는 현재 픽셀 작성 기록이며 재실행하면 같은 이름의 프로젝트와 PNG를 덮어쓰므로, Aseprite에서 추가 편집한 뒤 무심코 재실행하지 않는다. `preview.py`는 PNG를 수정하지 않고 비교표만 갱신한다.

```powershell
& "$env:LOCALAPPDATA\Programs\Aseprite\aseprite.exe" -b --script-param "root=$((Get-Location).Path)" --script docs/previews/aseprite-revision/author.lua
python docs/previews/aseprite-revision/preview.py
```

설치 실행 파일은 `%LOCALAPPDATA%\Programs\Aseprite\aseprite.exe`이며 시작 메뉴에도 Aseprite 바로가기가 있다. 프로그램과 빌드 자료는 저장소 및 Workshop 패키지 밖에 둔다.
