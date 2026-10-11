# 추적·유도 방식 정식 명칭

진(`DRAGON`) 작업에서 비교한 추적 방식의 정식 명칭과 계산식이다. 식의 `dir`은 진행 방향(라디안),
`bearing`은 표적 쪽 방향, `wrap()`은 각도를 −π..π로 접는 함수다.

## 현재 사용처

| 대상 | 방식 | 코드 |
| --- | --- | --- |
| 진 본체, 적이 있을 때 | 물결 추적 (Sinusoidal weaving pursuit) | `scripts/items/collectibles/dragon.lua` `updateMotion` |
| 진 본체, 적이 없을 때 | 벡터장 궤도 유도 (Vector field orbit guidance) | 같은 함수 |
| 진 본체의 방향 전환 | 회전 속도 자체를 가감속하는 조향 (rate- and acceleration-limited steering) | `steerHead` |
| 진의 몸통 | 경로 추종 체인 (follow-the-leader / trail following) | `pushTrail`, `layOut` |

## 방식별 정리

| 비교 화면 이름 | 정식 명칭 (영문) | 다른 이름 | 원리와 식 |
| --- | --- | --- | --- |
| 1. 직선 추적 | Pure pursuit | Reynolds의 Seek | 매 순간 표적의 현재 위치를 향한다. `dir = bearing`. 단순하지만 끝에서 급회전이 필요하다 |
| 2. 회전 제한 유도 | Pure pursuit with a bounded turn rate | turn-rate-limited homing, 곡률 제한 추적 (Dubins vehicle) | 표적 쪽으로 돌되 한 틱 최대 회전각을 넘지 않는다. `dir += clamp(wrap(bearing - dir), -maxTurn, maxTurn)`. 지나쳤다가 크게 돌아온다 |
| 3. 예측 추적 | Lead pursuit / Deviated pursuit | Reynolds의 Pursuit, 충돌 코스(collision course) | 표적이 도착할 즈음의 위치를 노린다. `aim = target + targetVelocity * (distance / speed)` |
| 4. 비례 항법 | Proportional navigation (PN) | TPN·PPN 변형, 항법상수 N=1이면 constant bearing(parallel navigation) | 시선각(LOS)의 회전량에 비례해 방향을 바꾼다. `dir += N * Δλ`, N은 보통 3~5. 시선이 돌지 않으면 충돌 코스에 있다는 원리 |
| 5. 스프링 추적 | Spring-damper (PD) pursuit | 감쇠 진동자, 임계감쇠 스프링 스무딩; 가까워질수록 감속하는 것은 Reynolds의 Arrive | `velocity += k * (target - position) - c * velocity`. 감쇠가 약하면 출렁인다 |
| 6. 감아 조이기 | Vector field orbit (loiter) guidance | Lyapunov vector field, standoff tracking; 반경을 줄이면 나선(spiral) | 궤도의 접선 방향에 반경 오차만큼 안/밖으로 기울인다. `want = φ + π/2 + atan(k * (r - R))` |
| 7. 물결 추적 | Sinusoidal weaving pursuit | weave manoeuvre, serpentine pursuit; Seek에 주기적 흔들림(Wander 계열)을 더한 것 | `want = bearing + A * sin(ω t)`, 회전 제한과 함께 쓴다 |
| 8. 관통 후 재돌진 | Fly-by (strafing) attack | slashing pass; 표준 유도 법칙이 아니라 회전 제한 추적이 표적을 지나치는 성질을 이용한 전술 | 빠른 속도와 작은 회전 한계로 표적을 관통한 뒤 크게 돌아 다시 진입 |
| 9. 관통 → 다음 적 | Chain targeting (target hopping) | 연쇄 표적, 튕기는 공격(ricochet)과 같은 표적 선택 | 유도 법칙이 아니라 표적 선택 규칙. 닿은 표적을 빠져나오면 그 표적을 제외한 가장 가까운 적으로 바꾼다 |

## 진에서 쓰는 보조 기법

- **회전 속도 가감속 조향**: 진행 방향을 바로 바꾸지 않고 회전 속도(`turnVel`)를 목표치로 서서히 바꾼다
  (`turnVel += clamp(asked - turnVel, -turnAccel, turnAccel)`). 경로의 곡률이 연속이 되어 머리 방향이 급변하지 않는다.
  리깅에서 루트 본이 부드럽게 움직이고 나머지 본이 따라가는 구조와 같다.
- **경로 추종 체인**: 머리가 지나간 점을 기록하고 각 마디를 그 경로 위의 고정 거리 지점에 둔다.
  인접 마디만 거리로 묶는 로프(최대 거리) 방식과 달리 마디가 뭉치거나 꺾이지 않는다. 절차적 뱀/지렁이
  애니메이션에서 쓰는 follow-the-leader 방식이다.
- **방향 반전 히스테리시스**: 측면 머리와 다리는 진행 방향이 수직을 충분히 넘어서고 일정 시간 유지될 때만
  좌우를 바꾼다. 경계 근처에서 깜빡이지 않는다.

## 출처

- Craig Reynolds, *Steering Behaviors For Autonomous Characters* (GDC 1999): Seek, Pursuit, Arrive, Wander, Path following.
- [Proportional navigation (Wikipedia)](https://en.wikipedia.org/wiki/Proportional_navigation): PN, TPN·PPN, 항법상수.
- [NPTEL 유도 강의 노트](https://archive.nptel.ac.in/content/storage2/courses/101108056/module5/lecture9.pdf): pure pursuit, deviated pursuit, PN 비교.
- [Constant bearing pursuit (arXiv)](https://arxiv.org/html/2512.00273v1): constant bearing = parallel navigation.
- [Nelson·Barber·McLain·Beard, vector field path following (BYU)](https://scholarsarchive.byu.edu/facpub/1536): 직선·원 궤도 벡터장 유도.
- [UAV loitering over a ground target (arXiv)](https://ar5iv.arxiv.org/html/1906.07000): Lyapunov 벡터장 궤도 유도.
