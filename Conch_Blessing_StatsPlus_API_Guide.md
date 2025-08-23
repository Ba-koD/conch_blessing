# Conch's Blessing 모드 - Stats+ API 사용법 가이드

이 문서는 **Conch's Blessing** 모드에서 Stats+ 모드의 외부 모드 API를 사용하는 방법을 상세하게 설명합니다.

## 📋 목차

- [개요](#개요)
- [Conch's Blessing 모드 구조](#conchs-blessing-모드-구조)
- [Stats+ API 기본 설정](#stats-api-기본-설정)
- [아이템 배수 시스템 구현](#아이템-배수-시스템-구현)
- [Stats+와 연동하기](#stats와-연동하기)
- [파일별 상세 구현](#파일별-상세-구현)
- [테스트 및 디버깅](#테스트-및-디버깅)
- [참고사항](#참고사항)

## 🎯 개요

**Conch's Blessing** 모드에서 Stats+ 모드의 API를 사용하여 게임 UI에 추가 정보를 표시할 수 있습니다. 이를 통해 아이템 배수, 특수 효과, 커스텀 계산값 등을 플레이어 스탯 옆에 깔끔하게 표시할 수 있습니다.

## 🏗️ Conch's Blessing 모드 구조

### 실제 폴더 구조

```
conch_blessing/
├── main.lua                           ← 모드 로더 (conch_blessing_core.lua 호출)
├── scripts/
│   ├── conch_blessing_core.lua        ← 모드 초기화 및 핵심 시스템
│   ├── conch_blessing_config.lua      ← 설정 및 상수 관리
│   ├── conch_blessing_mcm.lua         ← Mod Config Menu 연동
│   ├── conch_blessing_items.lua       ← 아이템 시스템 및 데이터
│   ├── conch_blessing_upgrade.lua     ← 업그레이드 시스템
│   ├── callback_manager.lua           ← 콜백 관리 시스템
│   ├── eid_language.lua               ← 다국어 지원
│   ├── template.lua                   ← 템플릿 시스템
│   ├── items/                         ← 개별 아이템 스크립트
│   │   ├── eternal_flame.lua          ← 영원한 불꽃
│   │   ├── injectable_steroids.lua    ← 주사용 스테로이드
│   │   ├── live_eye.lua               ← 살아있는 눈
│   │   ├── oral_steroids.lua          ← 경구용 스테로이드
│   │   └── void_dagger.lua            ← 공허의 단검
│   └── lib/                           ← 라이브러리
│       ├── isaacscript-common.lua     ← IsaacScript-Common
│       └── stats.lua                  ← 스탯 관리 시스템
├── content/                           ← 게임 콘텐츠
│   ├── items.xml                      ← 아이템 정의
│   └── itempools.xml                  ← 아이템 풀 설정
├── resources/                         ← 그래픽 리소스
│   └── gfx/
│       ├── effects/                    ← 이펙트 애니메이션
│       ├── font/                       ← 폰트 파일
│       └── items/                      ← 아이템 이미지
└── metadata.xml                       ← 모드 메타데이터
```

### 핵심 시스템 구조

- **conch_blessing_core.lua**: 모드의 메인 엔트리 포인트
- **conch_blessing_items.lua**: 아이템 데이터 테이블 및 시스템
- **stats.lua**: 스탯 계산 및 배수 시스템
- **callback_manager.lua**: 콜백 이벤트 관리
- **conch_blessing_upgrade.lua**: 아이템 업그레이드 시스템

## ⚙️ Stats+ API 기본 설정

### 1. 콜백 등록 (conch_blessing_core.lua에 추가)

```lua
-- scripts/conch_blessing_core.lua에 추가
-- Stats+ API 연결
ConchBlessing:AddCallback("STATS_PLUS_REGISTER", function(api)
    -- 여기서 Conch's Blessing의 기능들을 Stats+에 등록
    ConchBlessing.printDebug("Stats+ API에 연결되었습니다!")
    
    -- Conch's Blessing 애드온 등록
    api:register({
        id = "conchs-blessing-addon",
        name = "Conch's Blessing",
        providers = {}, -- 나중에 추가
        conditions = {}, -- 선택사항
        middleware = {} -- 선택사항
    })
end)
```

### 2. 사용 가능한 스탯 및 색상

```lua
-- Stats+에서 지원하는 스탯들
api.stat.speed      -- 이동속도
api.stat.tears      -- 공격속도 (연사)
api.stat.damage     -- 공격력
api.stat.range      -- 사거리
api.stat.shotSpeed  -- 탄속
api.stat.luck       -- 행운

-- 사용 가능한 색상들
"GREY"     -- 회색
"RED"      -- 빨간색
"GREEN"    -- 초록색
"BLUE"     -- 파란색
"ORANGE"   -- 주황색
"MAGENTA"  -- 마젠타
"CYAN"     -- 시안
```

## 🔧 아이템 배수 시스템 구현

### 1. 기존 스탯 시스템 활용 (scripts/lib/stats.lua)

```lua
-- scripts/lib/stats.lua에 Stats+ 연동 함수 추가
ConchBlessing.stats.statsPlusIntegration = {}

-- Stats+용 배수 데이터 제공자
function ConchBlessing.stats.statsPlusIntegration.createDamageProvider(api)
    return api:provider({
        id = "conchs-blessing-damage-multiplier",
        name = "Conch's Blessing 데미지",
        description = "Conch's Blessing 아이템들의 데미지 배수를 표시합니다",
        targets = {api.stat.damage},
        color = "BLUE",
        state = {
            multiplier = {initial = function() return 1.0 end},
            itemCount = {initial = function() return 0 end}
        },
        display = {
            value = {
                get = function(state) return state.multiplier end,
                format = function(multiplier) 
                    return "Conch: x" .. string.format("%.2f", multiplier) 
                end
            },
            change = {
                compute = function(prev, next)
                    if prev == 0 then return nil end
                    return next / prev
                end,
                isPositive = function(change) return change > 1 end,
                format = function(change) 
                    return "x" .. string.format("%.2f", change) 
                end
            }
        },
        mount = function(ctx)
            local player = ctx.player
            local playerIndex = player.Index
            
            -- 배수 업데이트 함수
            local function updateDisplay()
                -- Conch's Blessing 시스템에서 배수 가져오기
                local multiplier = ConchBlessing.stats.damage.getCurrentMultiplier(player)
                ctx.state.multiplier:set(multiplier)
                
                -- Conch's Blessing 아이템 개수 계산
                local itemCount = ConchBlessing.stats.countActiveItems(player)
                ctx.state.itemCount:set(itemCount)
            end
            
            -- 초기 업데이트
            updateDisplay()
            
            -- 이벤트 리스너들
            ConchBlessing:AddCallback(ModCallback.EVALUATE_CACHE, updateDisplay)
            
            return function()
                -- cleanup은 자동으로 처리됨
            end
        end
    })
end

-- 이동속도 배수 프로바이더
function ConchBlessing.stats.statsPlusIntegration.createSpeedProvider(api)
    return api:provider({
        id = "conchs-blessing-speed-multiplier",
        name = "Conch's Blessing 속도",
        description = "Conch's Blessing 아이템들의 이동속도 배수를 표시합니다",
        targets = {api.stat.speed},
        color = "GREEN",
        state = {
            multiplier = {initial = function() return 1.0 end}
        },
        display = {
            value = {
                get = function(state) return state.multiplier end,
                format = function(multiplier) 
                    return "Conch: x" .. string.format("%.2f", multiplier) 
                end
            }
        },
        mount = function(ctx)
            local player = ctx.player
            local playerIndex = player.Index
            
            local function updateDisplay()
                local multiplier = ConchBlessing.stats.speed.getCurrentMultiplier(player)
                ctx.state.multiplier:set(multiplier)
            end
            
            updateDisplay()
            ConchBlessing:AddCallback(ModCallback.EVALUATE_CACHE, updateDisplay)
            
            return function() end
        end
    })
end
```

### 2. Stats+ 연동 스크립트 (scripts/stats_plus_integration.lua 새로 생성)

```lua
-- scripts/stats_plus_integration.lua (새로 생성)
local ConchBlessing = ConchBlessing

-- Stats+ API 연결
ConchBlessing:AddCallback("STATS_PLUS_REGISTER", function(api)
    ConchBlessing.printDebug("Stats+ API에 연결되었습니다!")
    
    -- 프로바이더들 생성
    local damageProvider = ConchBlessing.stats.statsPlusIntegration.createDamageProvider(api)
    local speedProvider = ConchBlessing.stats.statsPlusIntegration.createSpeedProvider(api)
    
    -- Conch's Blessing 애드온 등록
    api:register({
        id = "conchs-blessing-addon",
        name = "Conch's Blessing",
        providers = {damageProvider, speedProvider}
    })
    
    ConchBlessing.print("Conch's Blessing이 Stats+에 성공적으로 등록되었습니다!")
end)
```

## 🔗 Stats+와 연동하기

### 1. 기존 아이템 시스템과 연동

```lua
-- scripts/conch_blessing_items.lua의 아이템 데이터에 Stats+ 표시 정보 추가
ConchBlessing.ItemData.LIVE_EYE = {
    -- ... 기존 데이터 ...
    
    -- Stats+ 표시용 데이터 추가
    statsPlus = {
        displayName = "Live Eye",
        description = "데미지 배수: x0.1 ~ x3.0",
        color = "RED",
        statType = "damage",
        multiplierRange = {0.75, 3.0}
    },
    
    -- ... 나머지 데이터 ...
}
```

### 2. 콜백 매니저와 연동

```lua
-- scripts/callback_manager.lua에 Stats+ 이벤트 추가
ConchBlessing.CallbackManager.StatsPlusEvents = {
    ITEM_ACTIVATED = "CONCH_BLESSING_ITEM_ACTIVATED",
    ITEM_DEACTIVATED = "CONCH_BLESSING_ITEM_DEACTIVATED",
    MULTIPLIER_UPDATED = "CONCH_BLESSING_MULTIPLIER_UPDATED"
}

-- Stats+ 이벤트 발생 함수
function ConchBlessing.CallbackManager.fireStatsPlusEvent(eventName, player, data)
    ConchBlessing:FireCallback(eventName, player, data)
    ConchBlessing.printDebug("Stats+ 이벤트 발생: " .. eventName)
end
```

## 📁 파일별 상세 구현

### 1. conch_blessing_core.lua - Stats+ 연동 추가

```lua
-- scripts/conch_blessing_core.lua에 추가
-- Stats+ 연동 스크립트 로드
local statsPlusSuccess, statsPlusErr = pcall(function()
    require("scripts/stats_plus_integration")
end)
if not statsPlusSuccess then
    ConchBlessing.printError("Stats+ 연동 로드 실패: " .. tostring(statsPlusErr))
end
```

### 2. stats.lua - Stats+ 지원 함수 추가

```lua
-- scripts/lib/stats.lua에 추가
-- Stats+용 배수 계산 함수
function ConchBlessing.stats.damage.getCurrentMultiplier(player)
    if not player then return 1.0 end
    
    local pdata = player:GetData()
    return pdata.conch_stats_damage_multiplier or 1.0
end

function ConchBlessing.stats.speed.getCurrentMultiplier(player)
    if not player then return 1.0 end
    
    local pdata = player:GetData()
    return pdata.conch_stats_speed_multiplier or 1.0
end

-- 활성 아이템 개수 계산
function ConchBlessing.stats.countActiveItems(player)
    if not player then return 0 end
    
    local count = 0
    for itemId, itemData in pairs(ConchBlessing.ItemData) do
        if player:HasCollectible(itemData.id) then
            count = count + 1
        end
    end
    
    return count
end
```

### 3. 개별 아이템 스크립트 - Stats+ 이벤트 발생

```lua
-- scripts/items/live_eye.lua 예시
function liveeye.onBeforeChange(player, itemId)
    -- ... 기존 로직 ...
    
    -- Stats+ 이벤트 발생
    ConchBlessing.CallbackManager.fireStatsPlusEvent(
        ConchBlessing.CallbackManager.StatsPlusEvents.ITEM_ACTIVATED,
        player,
        {
            itemId = itemId,
            itemName = "Live Eye",
            effectType = "damage_multiplier"
        }
    )
end
```

## 🧪 테스트 및 디버깅

### 1. 디버그 출력 (기존 시스템 활용)

```lua
-- 기존 디버그 함수 활용
ConchBlessing.printDebug("Stats+ 연동 테스트")
ConchBlessing.print("Stats+ 프로바이더 등록 완료")
```

### 2. Stats+ 연동 상태 확인

```lua
-- Stats+ API 연결 상태 확인
function ConchBlessing.checkStatsPlusConnection()
    if ConchBlessing.statsPlusAPI then
        ConchBlessing.printDebug("Stats+ API 연결됨")
        return true
    else
        ConchBlessing.printDebug("Stats+ API 연결 안됨")
        return false
    end
end
```

## 📚 참고사항

### 1. 파일 로딩 순서

1. **main.lua** - 모드 로더
2. **conch_blessing_core.lua** - 핵심 시스템 초기화
3. **conch_blessing_config.lua** - 설정 로드
4. **stats.lua** - 스탯 시스템
5. **conch_blessing_items.lua** - 아이템 시스템
6. **stats_plus_integration.lua** - Stats+ 연동 (새로 생성)
7. **개별 아이템 스크립트들**

### 2. 기존 시스템과의 통합

- **IsaacScript-Common**: 기존 ISC 기능들과 호환
- **콜백 매니저**: Stats+ 이벤트를 기존 이벤트 시스템과 통합
- **스탯 시스템**: 기존 배수 계산 로직을 Stats+ 표시에 활용

### 3. 성능 최적화

- 배수 계산은 필요할 때만 수행
- Stats+ 이벤트는 중요한 변경사항만 발생
- 플레이어별 데이터는 기존 시스템과 공유

### 4. 호환성

- Stats+ 모드가 로드된 후에만 API 사용
- 기존 Conch's Blessing 기능들과 완벽 호환
- 다른 모드와의 충돌 방지를 위한 고유 ID 사용

---

이 문서는 **Conch's Blessing** 모드에서 Stats+ 모드의 외부 모드 API를 사용하는 방법을 상세하게 설명합니다. 실제 모드 구조에 맞춰 작성되었으며, 기존 시스템과의 통합 방법을 포함합니다. 