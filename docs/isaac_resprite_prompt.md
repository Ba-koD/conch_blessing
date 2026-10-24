# 아이작 아이템 리스프라이트 프롬프트

2026-10-24. [실제 스프라이트 관찰 기록](isaac_item_sprite_study.md)과 사용자가 선택한 [십이지 4차](previews/zodiac-v4/zodiac-overview.png)를 바탕으로 정리했다. 바닐라·Epiphany·Auri·Astro Items에서 관찰한 제작 특징과 우리 모드의 굵은 외곽선 취향을 함께 반영한다. 새로 정리한 재사용 템플릿이며, 이 프롬프트 한 번만으로 기존 4차 결과가 생성되었다는 뜻은 아니다. 4차는 생성 원안 이후 네이티브 픽셀 수정으로 완성했다.

## 이 프로젝트에서 바로 요청할 때

아래 블록의 대괄호 부분을 채워서 사용한다. 원본 아이템의 형태·색·특징을 먼저 정하고, 변경 요청에 없는 부분은 유지한다.

후속 수정은 사용자가 '새 시안'을 선택하거나 '완전 재설계'를 지정하지 않았다면 **런타임 원본에서** 시작한다. 언급 없는 아이템에는 이전 제안을 이어 쓰지 않고 원본 PNG를 그대로 유지한다. 수정 자체는 처음부터 32×32 격자에서 진행한다. 비교표에 원본 유지·원본 수정·이전 시안 채택·새 디자인을 구분한다.

새 아이템 그림은 **빈 32×32 캔버스에서 처음부터** 픽셀을 배치한다. 큰 생성 원안을 만든 뒤 축소·트레이싱·재구성하는 흐름을 기본으로 쓰지 않는다. 이는 2026-10-24 사용자의 명시적인 작업 방식 수정이다. 기존 원본 수정은 원본의 네이티브 격자에서 시작한다. 칼날/몸체의 비율, 평행선, 내부 빈틈, 겹침, 재질별 색면을 실제 1배와 정수 확대에서 확인하고 직접 고친다. 크기·알파 검사나 좌표로 도형을 그린 사실만으로 그림 품질을 증명하지 않는다.

사용자가 검토본의 나머지는 수정할 필요 없다고 하면 그 선택을 다음 작업의 기준으로 유지한다. 원본을 조금 밝게 해 달라는 요청은 형태·색조 관계·검정 외곽·알파를 보존하는 작은 명도 수정이다. 새 팔레트나 디테일 추가로 확대 해석하지 않는다.

```text
docs/isaac_resprite_prompt.md와 docs/isaac_item_sprite_study.md를 읽고,
다음 아이템을 우리 모드의 아이작 그림체로 리스프라이트해줘.

대상 아이템 / 원본 이미지: [아이템 이름, 파일 경로 또는 첨부 이미지]
핵심 형태: [작은 병, 부러진 칼, 눈 하나, 동물 머리 등 한 가지]
반드시 유지할 특징: [색 조합, 기울기, 비율, 표식, 핵심 소품]
바꿀 부분: [외곽선 두께, 복잡한 음영 정리, 겹침 수정 등]
아이템 성격: [기괴함 / 묵직함 / 우스꽝스러움 / 위엄 / 원본 유지]
능력을 암시할 모티브: [한 가지만, 불필요하면 없음]

원본과 실제 참고 PNG를 먼저 보고 각각 수정 대상과 화풍 참고로 구분해.
우리 모드의 승인된 십이지 4차 PNG를 선 굵기와 단순화 수준의 참고로 써.
바깥 윤곽선은 불투명한 검정에 가까운 색으로 약 2픽셀 두께를 목표로 하고,
눈·입·틈 같은 내부 구획은 필요한 만큼만 얇게 남겨줘.
색만 진하게 바꾸지 말고 실제 32×32에서 선폭이 느껴지게 해줘.
단순한 큰 색면, 제한된 팔레트, 또렷한 실루엣과 투명 여백을 유지해.
동물, 얼굴, 왕관, 후광을 원래 없는 아이템에 임의로 붙이지 마.

빈 32×32 캔버스에서 처음부터 픽셀 단위로 설계하고 그려줘.
큰 생성 원안을 먼저 만든 뒤 축소하거나 옮겨 그리는 방식은 쓰지 마.
완성 PNG의 1배와 정수배 최근접 확대, 수정 전후를 함께 보여줘.
우선 docs/previews/ 아래 새 버전으로 저장해줘.
게임 적용을 별도로 요청한 경우에만 런타임 파일을 교체하고 생성 파일을 갱신해줘.
```

## 사용자가 별도로 큰 생성 원안을 요청한 경우에만 쓰는 본문

아래 생성 도구용 본문은 기본 32×32 직접 작성 흐름에서 사용하지 않는다. 사용자가 큰 구상 그림부터 만들라고 명시한 경우에만 사용한다.

`[ITEM]` 등의 값을 실제 설명으로 바꾼다. 원본을 **Image 1**, 화풍 참고를 **Image 2**로 함께 제공한다. 파일 경로를 텍스트에 적는 것만으로 이미지가 도구에 전달되지는 않는다. 코드 에이전트는 로컬 파일을 먼저 열어 확인한 뒤 이미지 참조로 넘긴다.

```text
Use case: style-transfer / precise-object-edit.
Asset: one collectible item sprite for The Binding of Isaac.

Image 1 is the EDIT TARGET: [ITEM / ORIGINAL IMAGE].
Image 2 is a STYLE REFERENCE ONLY: an approved native 32x32 item sprite
from this project's zodiac-v4 set, or inspected vanilla/mod references.
Use the reference's pixel construction, outline weight and color economy.
Do not copy its subject, distinctive anatomy, decorations or composition.

SUBJECT: [ONE PRIMARY OBJECT OR CREATURE SHAPE].
PRESERVE: [IDENTIFYING SILHOUETTE, ORIENTATION, PROPORTIONS, COLORS, MOTIF].
CHANGE ONLY: [REQUESTED CHANGES].
MOOD: [ITEM'S INTENDED MOOD; OTHERWISE KEEP THE ORIGINAL].
ABILITY MOTIF: [ONE SMALL INTEGRATED CUE, OR NONE].

Design every feature as if the entire canvas had only 32 columns and
32 rows. Each logical pixel is one flat square of equal size. Use a
compact, slightly handmade silhouette with broad, uninterrupted color
clusters. Preserve the item's identity at actual gameplay size.

Use an opaque near-black outer contour, approximately #08080b. Target
about TWO logical pixels along the main outer silhouette, with selective
one-pixel tips and interior details where needed for readability. Make
the contour physically thicker, not merely darker. Do not thicken eyes,
mouths and internal seams indiscriminately. Keep openings between horns,
ears, handles and limbs readable. Keep at least one transparent pixel of
canvas padding; do not clip or force the object to fill the whole canvas.

Start with roughly 5-8 opaque colors total, including the outline. Use
one base color and one muted shadow per material, with a sparse highlight
only where useful. Add another color only if essential to separate a
material or focal point. Prefer upper-left light and simple lower-right
shadow clusters. Preserve the source palette's identity while simplifying.

The primary object must read before any secondary motif. Keep carried
objects below or beside a face, without covering identifying features.
Honor the original emotion. Use dignity only when requested: convey it
through a steady gaze, stable posture and strong simple shapes, not extra
armor, crowns, jewelry, muscular anatomy or ornamental effects.

Use hard pixel edges and genuine transparent background. No antialiasing,
soft gradients, blur, glow haze, dithering, fur strands, scale textures,
realistic anatomy, tiny decorative particles or detailed portrait shading.
No background scene, ground shadow, pedestal, frame, labels, UI or text.
Do not add a face or turn an object into a mascot unless requested.

Output ONE isolated sprite, not a contact sheet. If the tool outputs a
larger image, keep the drawing at the visual complexity of a single
32x32 sprite enlarged by nearest neighbor; do not invent smaller details.
The generated result is a draft for direct native-grid finishing.
```

## 한 부분만 고칠 때 붙일 문장

| 수정 목표 | 추가 지시 |
| --- | --- |
| 윤곽선 강화 | `Change only the outer contour: reinforce it by one native pixel where padding allows. Preserve all existing interior colors and features. Keep transparent gaps open. Do not redraw or enlarge the subject's interior.` |
| 복잡함 줄이기 | `Merge tiny shading fragments into broad base and shadow clusters. Preserve the recognizable silhouette and the single identifying motif. Remove surface texture before removing structural features.` |
| 얼굴 가림 해소 | `Keep the entire face, eyes, muzzle and chin visible. Shrink or move the carried object below the chin or beside the body. Preserve the character's expression and identity.` |
| 위엄 보강 — 해당 콘셉트만 | `Convey solemn authority through steady eyes, a stable pose and a broad simple forehead or jaw where anatomically appropriate. Keep the tiny Isaac proportions and flat fills. Add no regalia, effects or realistic muscle detail.` |

## 참고 선택과 마무리

- 바닐라에서 관찰한 외곽선은 대체로 1픽셀이며 필요한 곳에서 굵어진다. 위 템플릿의 **약 2픽셀**은 사용자가 선택한 우리 모드의 최근 표현 기준이다. 모든 바닐라 스프라이트가 2픽셀이라는 뜻은 아니다. 가는 도구·작은 틈은 형태를 읽을 수 있게 조절한다.
- 승인된 스타일 참고는 `docs/previews/zodiac-v4/icons/`의 개별 PNG다. 모음표는 비교용이며, 그림 하나를 수정할 때는 개별 PNG를 우선한다. 십이지의 동물 모양이나 위엄을 모든 아이템에 강요하지 않는다.
- 관찰 기록의 바닐라·다른 모드 파일은 제작 특징을 보는 읽기 전용 자료다. 그 모드의 고유 형상이나 자산을 복제하지 않는다. 더 상세한 `azure_dragon.png` 길동무 그림은 이번 저밀도 아이템 기준으로 사용하지 않는다.
- 최종 PNG는 실제 **32×32 RGBA**, 이 표현 방식에서는 알파 **0 또는 255**, 투명 여백과 또렷한 색면을 갖도록 직접 정리한다. 생성 도구에 규격을 적었다고 실제 출력이 규격을 지키는 것은 아니므로 확인한다.
- 1배에서 정체성·표정·소품·겹침을 보고, 4배 또는 5배 최근접 확대에서 선폭·틈·고립 픽셀을 확인한다. 밝은 배경과 어두운 배경 모두에서 확인하며, 확대본은 최종 PNG에서 만든다.
- 게임 적용을 요청받았다면 승인된 PNG를 정확한 런타임 경로에 연결하고 `python generate_xml.py`로 죽음 화면 아이콘까지 갱신한다. 해당 아이템이 업그레이드 HTML 카탈로그에 있으면 `python sync_upgrade_preview.py`도 실행한다. 게임 리소스 반영 확인에는 완전한 재시작이 필요하다.

기존 원안 프롬프트는 `previews/zodiac-v2/prompts.json`, 산군·토끼 수정 원안은 `previews/zodiac-v3/prompts.json`에 남아 있다. 4차 윤곽선 수정의 최종 픽셀 원본은 `previews/zodiac-v4/pixels.json`이다.
