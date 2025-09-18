// Conch's Blessing Language Texts
// Auto-generated language support

const texts = {
    en: {
        // Page titles and headers
        title: "🐚 <a href=\"https://steamcommunity.com/sharedfiles/filedetails/?id=3545334858\" target=\"_blank\">Conch's Blessing</a>",
        subtitle: "Conch's Blessing - Item Guide",
        introduction: "Introduction",
        items: "Items",
        keyFeatures: "Key Features",
        
        // Language selector
        languageLabel: "Language:",
        autoDetect: "Auto Detect",
        korean: "Korean",
        english: "English",
        
        // Introduction text
        introText: "Conch's Blessing is a mod that adds a 'Conch's Blessing' upgrade system to The Binding of Isaac: Repentance. It transforms existing items with polished visuals and allows fine customization of language, spawn, and timing.",
        
        // Search and filter
        searchPlaceholder: "Search by item name, Origin...",
        searchButton: "Search",
        typeLabel: "Type:",
        allTypes: "All Types",
        passive: "Passive",
        active: "Active",
        trinket: "Trinket",
        familiar: "Familiar",
        flagLabel: "Flag:",
        allFlags: "All Flags",
        positive: "Positive",
        neutral: "Neutral",
        negative: "Negative",
        sortLabel: "Sort:",
        byName: "By Name",
        byQuality: "By Quality",
        byType: "By Type",
        
        // Features
        itemUpgrade: "Item Upgrade Sequence",
        itemUpgradeDesc: "Upgrade system that naturally connects Before → Morph → After",
        multiLanguage: "Multi-language Support",
        multiLanguageDesc: "HUD/EID popups in Korean/English",
        naturalSpawn: "Natural Spawn Toggle",
        naturalSpawnDesc: "Enable/disable mod item spawns via MCM",
        
        // Footer
        copyright: "© 2025 Conch's Blessing Mod",
        required: "Required: <a href=\"https://steamcommunity.com/sharedfiles/filedetails/?id=3540206030\" target=\"_blank\">Magic Conch</a>",
        
        // Modal and UI
        noResults: "No results found",
        noResultsDesc: "Try different search terms or filters",
        workingInProgress: "Work in progress item",
        
        // Item properties
        pool: "Pool",
        tags: "Tags",
        origin: "Origin",
        flag: "Flag",
        flagDesc: "Magic Conch's answer (Positive, Neutral, Negative)",
        
        // Synergies
        synergies: "Synergies",
        synergyNoDesc: "No synergy description"
    },
    
    kr: {
        // Page titles and headers
        title: "🐚 <a href=\"https://steamcommunity.com/sharedfiles/filedetails/?id=3545334858\" target=\"_blank\">Conch's Blessing</a>",
        subtitle: "소라고동의 축복 - 아이템 가이드",
        introduction: "소개",
        items: "아이템 목록",
        keyFeatures: "주요 기능",
        
        // Language selector
        languageLabel: "언어:",
        autoDetect: "자동 감지",
        korean: "한국어",
        english: "English",
        
        // Introduction text
        introText: "Conch's Blessing은 아이작의 번제에 '소라고동의 축복' 업그레이드 시스템을 추가하는 모드입니다. 기존 아이템을 세련된 연출과 함께 변환하고, 언어/스폰/타이밍을 세밀하게 커스터마이징할 수 있습니다.",
        
        // Search and filter
        searchPlaceholder: "아이템 이름, Origin으로 검색...",
        searchButton: "검색",
        typeLabel: "타입:",
        allTypes: "모든 타입",
        passive: "패시브",
        active: "액티브",
        trinket: "장신구",
        familiar: "패밀리어",
        flagLabel: "플래그:",
        allFlags: "모든 플래그",
        positive: "긍정적",
        neutral: "중립적",
        negative: "부정적",
        sortLabel: "정렬:",
        byName: "이름순",
        byQuality: "품질순",
        byType: "타입순",
        
        // Features
        itemUpgrade: "아이템 업그레이드 연출",
        itemUpgradeDesc: "Before → Morph → After로 자연스럽게 연결되는 업그레이드 시스템",
        multiLanguage: "다국어 지원",
        multiLanguageDesc: "HUD/EID 팝업 한/영 자동 적용",
        naturalSpawn: "자연 스폰 토글",
        naturalSpawnDesc: "MCM에서 모드 아이템 자연 스폰 ON/OFF",
        
        // Footer
        copyright: "© 2025 Conch's Blessing Mod",
        required: "필수 모드: <a href=\"https://steamcommunity.com/sharedfiles/filedetails/?id=3540206030\" target=\"_blank\">Magic Conch</a>",
        
        // Modal and UI
        noResults: "검색 결과가 없습니다",
        noResultsDesc: "다른 검색어나 필터를 시도해보세요",
        workingInProgress: "작업중인 아이템입니다",
        
        // Item properties
        pool: "풀",
        tags: "태그",
        origin: "원본",
        flag: "플래그",
        flagDesc: "마법의 소라고둥의 답변 (긍정적, 중립적, 부정적)",
        
        // Synergies
        synergies: "시너지",
        synergyNoDesc: "시너지 설명 없음"
    }
};

// 언어 감지 및 자동 선택 함수
function detectAndSetLanguage() {
    const browserLang = navigator.language || navigator.userLanguage;
    const langCode = browserLang.split('-')[0].toLowerCase();
    
    // 지원하는 언어인지 확인
    if (texts[langCode]) {
        return langCode;
    } else {
        return 'en'; // 기본값은 영어
    }
}

// 텍스트 가져오기 함수
function getText(key, language = null) {
    const lang = language || getDisplayLanguage();
    return texts[lang]?.[key] || texts['en'][key] || key;
} 