const SUPPORTED_LANGUAGES = ['kr', 'en'];

let currentLanguage = 'auto';
let detectedLanguage = 'en';

let allItems = {};
let filteredItems = {};

function detectBrowserLanguage() {
    return detectAndSetLanguage();
}

function changeLanguage(lang) {
    currentLanguage = lang;
    
    const languageSelect = document.getElementById('languageSelect');
    if (languageSelect) {
        languageSelect.value = lang;
    }
    
    updatePageContent();
    
    localStorage.setItem('conch_blessing_language', lang);
    
    console.log('Language changed to:', lang);
}

function initializeLanguage() {
    const savedLanguage = localStorage.getItem('conch_blessing_language');
    if (savedLanguage && SUPPORTED_LANGUAGES.includes(savedLanguage)) {
        currentLanguage = savedLanguage;
        detectedLanguage = savedLanguage;
    } else {
        detectedLanguage = detectBrowserLanguage();
        currentLanguage = 'auto';
    }
    
    const languageSelect = document.getElementById('languageSelect');
    if (languageSelect) {
        languageSelect.value = currentLanguage;
    }
    
    console.log('Language initialized:', { currentLanguage, detectedLanguage });
}

function getDisplayLanguage() {
    if (currentLanguage === 'auto') {
        return detectedLanguage;
    }
    return currentLanguage;
}

function getLocalizedText(item, field, lang) {
    if (item[field] && item[field][lang]) {
        return item[field][lang];
    }
    return null;
}

function initializeSearchAndFilter() {
    const searchInput = document.getElementById('searchInput');
    const searchBtn = document.getElementById('searchBtn');
    const typeFilter = document.getElementById('typeFilter');
    const flagFilter = document.getElementById('flagFilter');
    const sortFilter = document.getElementById('sortFilter');
    
    if (searchInput) {
        searchInput.addEventListener('input', performSearch);
        searchInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                performSearch();
            }
        });
    }
    
    if (searchBtn) {
        searchBtn.addEventListener('click', performSearch);
    }
    
    if (typeFilter) {
        typeFilter.addEventListener('change', performSearch);
    }
    
    if (flagFilter) {
        flagFilter.addEventListener('change', performSearch);
    }
    
    if (sortFilter) {
        sortFilter.addEventListener('change', performSearch);
    }
}

function performSearch() {
    const searchTerm = document.getElementById('searchInput')?.value.toLowerCase() || '';
    const typeFilter = document.getElementById('typeFilter')?.value || 'all';
    const flagFilter = document.getElementById('flagFilter')?.value || 'all';
    const sortBy = document.getElementById('sortFilter')?.value || 'name';
    
    console.log('Search performed:', { searchTerm, typeFilter, flagFilter, sortBy });
    console.log('allItems count:', Object.keys(allItems).length);
    
    const container = document.getElementById('itemsContainer');
    if (container) {
        container.classList.add('searching');
    }
    
    filteredItems = { ...allItems };
    
    if (searchTerm) {
        console.log('Filtering by search term:', searchTerm);
        const beforeCount = Object.keys(filteredItems).length;
        
        filteredItems = Object.fromEntries(
            Object.entries(filteredItems).filter(([key, item]) => {
                const currentLangName = getLocalizedText(item, 'names', getDisplayLanguage()) || '';
                const englishName = getLocalizedText(item, 'names', 'en') || '';
                
                if (currentLangName.toLowerCase().includes(searchTerm)) {
                    console.log(`Item ${key} matched by current language name: "${currentLangName}" contains "${searchTerm}"`);
                    return true;
                }
                
                if (englishName.toLowerCase().includes(searchTerm)) {
                    console.log(`Item ${key} matched by English name: "${englishName}" contains "${searchTerm}"`);
                    return true;
                }
                
                if (item.origin) {
                    const originLower = item.origin.toLowerCase().replace(/_/g, ' ');
                    if (originLower.includes(searchTerm)) {
                        console.log(`Item ${key} matched by origin: "${item.origin}" (${originLower}) contains "${searchTerm}"`);
                        return true;
                    }
                }
                
                return false;
            })
        );
        
        console.log('Filtered results:', { beforeCount, afterCount: Object.keys(filteredItems).length });
    } else {
        filteredItems = { ...allItems };
        console.log('No search term - showing all items');
    }
    
                if (typeFilter !== 'all') {
                    const sourceItems = Object.keys(filteredItems).length > 0 ? filteredItems : allItems;
                    filteredItems = Object.fromEntries(
                        Object.entries(sourceItems).filter(([key, item]) => {
                            return item.type === typeFilter;
                        })
                    );
                    console.log(`Type filtered by ${typeFilter}: ${Object.keys(filteredItems).length} items found`);
                }
    
                if (flagFilter !== 'all') {
                    const sourceItems = Object.keys(filteredItems).length > 0 ? filteredItems : allItems;
                    filteredItems = Object.fromEntries(
                        Object.entries(sourceItems).filter(([key, item]) => {
                            return item.flag && item.flag.toLowerCase() === flagFilter.toLowerCase();
                        })
                    );
                    console.log(`Flag filtered by ${flagFilter}: ${Object.keys(filteredItems).length} items found`);
                }
    
    if (Object.keys(filteredItems).length > 0) {
        console.log(`Sorting ${Object.keys(filteredItems).length} items by: ${sortBy}`);
        
        const sortedItems = Object.entries(filteredItems).sort(([keyA, itemA], [keyB, itemB]) => {
            switch (sortBy) {
                case 'name':
                    const nameA = getLocalizedText(itemA, 'names', getDisplayLanguage()) || '';
                    const nameB = getLocalizedText(itemB, 'names', getDisplayLanguage()) || '';
                    return nameA.localeCompare(nameB, getDisplayLanguage() === 'kr' ? 'ko' : 'en');
                
                case 'quality':
                    const qualityA = itemA.quality || 0;
                    const qualityB = itemB.quality || 0;
                    console.log(`Comparing quality: ${keyA}(${qualityA}) vs ${keyB}(${qualityB})`);
                    return qualityB - qualityA;
                
                case 'type':
                    const typeA = itemA.type || 'passive';
                    const typeB = itemB.type || 'passive';
                    return typeA.localeCompare(typeB);
                
                default:
                    return 0;
            }
        });
        
        filteredItems = Object.fromEntries(sortedItems);
        console.log(`Sorting completed. First few items:`, Object.keys(filteredItems).slice(0, 3));
    } else {
        console.log('No items to sort - filteredItems is empty');
    }
    
    updateItemsDisplay();
}

function updatePageContent() {
    const displayLang = getDisplayLanguage();
    
    updatePageTexts(displayLang);
    
    updateItemsDisplay();
    
    updateLanguageSelectorText();
    
    updateModalContent(displayLang);
}

function updatePageTexts(displayLang) {
    const pageTitle = document.getElementById('pageTitle');
    const pageSubtitle = document.getElementById('pageSubtitle');
    if (pageTitle) pageTitle.textContent = getText('title', displayLang);
    if (pageSubtitle) pageSubtitle.textContent = getText('subtitle', displayLang);
    
    const languageLabel = document.getElementById('languageLabel');
    if (languageLabel) languageLabel.textContent = getText('languageLabel', displayLang);
    
    const introTitle = document.getElementById('introTitle');
    const introText = document.getElementById('introText');
    if (introTitle) introTitle.textContent = getText('introduction', displayLang);
    if (introText) introText.textContent = getText('introText', displayLang);
    
    const itemsTitle = document.getElementById('itemsTitle');
    if (itemsTitle) itemsTitle.textContent = getText('items', displayLang);
    
    const searchInput = document.getElementById('searchInput');
    const searchBtn = document.getElementById('searchBtn');
    if (searchInput) searchInput.placeholder = getText('searchPlaceholder', displayLang);
    if (searchBtn) searchBtn.textContent = getText('searchButton', displayLang);
    
    const typeLabel = document.getElementById('typeLabel');
    const flagLabel = document.getElementById('flagLabel');
    const sortLabel = document.getElementById('sortLabel');
    if (typeLabel) typeLabel.textContent = getText('typeLabel', displayLang);
    if (flagLabel) flagLabel.textContent = getText('flagLabel', displayLang);
    if (sortLabel) sortLabel.textContent = getText('sortLabel', displayLang);
    
    const allTypes = document.getElementById('allTypes');
    const passive = document.getElementById('passive');
    const active = document.getElementById('active');
    if (allTypes) allTypes.textContent = getText('allTypes', displayLang);
    if (passive) passive.textContent = getText('passive', displayLang);
    if (active) active.textContent = getText('active', displayLang);
    
    const allFlags = document.getElementById('allFlags');
    const positive = document.getElementById('positive');
    const neutral = document.getElementById('neutral');
    const negative = document.getElementById('negative');
    if (allFlags) allFlags.textContent = getText('allFlags', displayLang);
    if (positive) positive.textContent = getText('positive', displayLang);
    if (neutral) neutral.textContent = getText('neutral', displayLang);
    if (negative) negative.textContent = getText('negative', displayLang);
    
    const byName = document.getElementById('byName');
    const byQuality = document.getElementById('byQuality');
    const byType = document.getElementById('byType');
    if (byName) byName.textContent = getText('byName', displayLang);
    if (byQuality) byQuality.textContent = getText('byQuality', displayLang);
    if (byType) byType.textContent = getText('byType', displayLang);
    
    const featuresTitle = document.getElementById('featuresTitle');
    const itemUpgradeTitle = document.getElementById('itemUpgradeTitle');
    const itemUpgradeDesc = document.getElementById('itemUpgradeDesc');
    const multiLanguageTitle = document.getElementById('multiLanguageTitle');
    const multiLanguageDesc = document.getElementById('multiLanguageDesc');
    const naturalSpawnTitle = document.getElementById('naturalSpawnTitle');
    const naturalSpawnDesc = document.getElementById('naturalSpawnDesc');
    
    if (featuresTitle) featuresTitle.textContent = getText('keyFeatures', displayLang);
    if (itemUpgradeTitle) itemUpgradeTitle.textContent = getText('itemUpgrade', displayLang);
    if (itemUpgradeDesc) itemUpgradeDesc.textContent = getText('itemUpgradeDesc', displayLang);
    if (multiLanguageTitle) multiLanguageTitle.textContent = getText('multiLanguage', displayLang);
    if (multiLanguageDesc) multiLanguageDesc.textContent = getText('multiLanguageDesc', displayLang);
    if (naturalSpawnTitle) naturalSpawnTitle.textContent = getText('naturalSpawn', displayLang);
    if (naturalSpawnDesc) naturalSpawnDesc.textContent = getText('naturalSpawnDesc', displayLang);
    
    const copyright = document.getElementById('copyright');
    const required = document.getElementById('required');
    if (copyright) copyright.textContent = getText('copyright', displayLang);
    if (required) required.textContent = getText('required', displayLang);
}

function updateLanguageSelectorText() {
    const displayLang = getDisplayLanguage();
    const languageSelect = document.getElementById('languageSelect');
    if (languageSelect) {
        Array.from(languageSelect.options).forEach(option => {
            if (option.id === 'autoDetect') {
                option.textContent = getText('autoDetect', displayLang);
            } else if (option.id === 'korean') {
                option.textContent = getText('korean', displayLang);
            } else if (option.id === 'english') {
                option.textContent = getText('english', displayLang);
            }
        });
    }
}

function updateItemsDisplay() {
    const container = document.getElementById('itemsContainer');
    if (!container) return;
    
    const isSearching = container.classList.contains('searching');
    
    container.innerHTML = '';
    
    if (isSearching) {
        container.classList.add('searching');
    }
    
    if (typeof items !== 'undefined') {
        if (Object.keys(allItems).length === 0) {
            allItems = items;
        }
        
        const searchTerm = document.getElementById('searchInput')?.value || '';
        const typeFilter = document.getElementById('typeFilter')?.value || 'all';
        const flagFilter = document.getElementById('flagFilter')?.value || 'all';
        const sortBy = document.getElementById('sortFilter')?.value || 'name';
        
        const hasActiveFilters = searchTerm || typeFilter !== 'all' || flagFilter !== 'all';
        const hasSorting = true;
        
        let itemsToDisplay;
        if (hasActiveFilters || (hasSorting && Object.keys(filteredItems).length > 0)) {
            itemsToDisplay = filteredItems;
        } else {
            itemsToDisplay = allItems;
        }
        console.log('Items to display:', { 
            filteredCount: Object.keys(filteredItems).length, 
            allCount: Object.keys(allItems).length,
            displayCount: Object.keys(itemsToDisplay).length 
        });
        
        Object.entries(itemsToDisplay).forEach(([key, item]) => {
            const itemCard = createItemCard(key, item);
            
            if (container.classList.contains('searching')) {
                itemCard.style.animation = 'none';
            }
            
            container.appendChild(itemCard);
        });
        
        if (Object.keys(itemsToDisplay).length === 0) {
            const noResultsMsg = document.createElement('div');
            noResultsMsg.className = 'no-results';
            noResultsMsg.innerHTML = `
                <div class="no-results-content">
                    <h3>${getText('noResults', getDisplayLanguage())}</h3>
                    <p>${getText('noResultsDesc', getDisplayLanguage())}</p>
                </div>
            `;
            container.appendChild(noResultsMsg);
        }
        
        container.classList.remove('searching');
    } else {
        console.error('items.js not loaded or items variable not found');
        container.innerHTML = '<p class="error-message">아이템 데이터를 불러올 수 없습니다.</p>';
    }
}

function createItemCard(key, item) {
    const displayLang = getDisplayLanguage();
    const card = document.createElement('div');
    card.className = 'item-card';
    
    const isWorkingNow = item.quality === undefined;
    
    const qualityStars = !isWorkingNow ? '⭐'.repeat(item.quality || 3) : '';
    
    const poolText = !isWorkingNow ? formatPoolText(item.pools, displayLang) : '';
    
    const tagsText = !isWorkingNow ? (item.tags || 'offensive') : '';
    
    const itemName = getLocalizedText(item, 'names', displayLang) || 'Unknown';
    const itemDescription = getLocalizedText(item, 'descriptions', displayLang) || '';
    
    let effects = [];
    if (item.eids && item.eids[displayLang]) {
        effects = item.eids[displayLang];
    } else {
        effects = [itemDescription || '효과 정보 없음'];
    }
    
    card.innerHTML = `
        <div class="item-header">
            <div class="item-image-container">
                <img src="${item.gfx || `resources/gfx/items/collectibles/${key.toLowerCase()}.png`}" 
                     alt="${itemName}" 
                     class="item-image" 
                     onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                <div class="item-name-fallback" style="display:none;">
                    <div class="fallback-icon">🎯</div>
                    <div class="fallback-text">${itemName}</div>
                </div>
            </div>
            <div class="item-info">
                <h3>${itemName}</h3>
                ${!isWorkingNow ? `<span class="item-type ${item.type || 'passive'}">${(item.type || 'passive').toUpperCase()}</span>` : ''}
                ${!isWorkingNow ? `<div class="quality-stars">${qualityStars}</div>` : ''}
            </div>
        </div>
        
        <div class="item-description">${itemDescription}</div>
        
        <div class="item-effects">
            <h4 data-kr="효과" data-en="Effects">효과</h4>
            <ul class="effect-list">
                ${effects.map(effect => `<li>${effect}</li>`).join('')}
            </ul>
        </div>
        
        ${!isWorkingNow ? `
        <div class="item-stats">
            <div class="stats-group">
                <span class="stat-tag">Pool: ${poolText}</span>
                <span class="stat-tag">Tags: ${tagsText}</span>
                ${item.shopprice ? `<span class="stat-tag">Shop: ${item.shopprice}$</span>` : ''}
                ${item.devilprice ? `<span class="stat-tag">Devil: ${item.devilprice}♥</span>` : ''}
                ${item.maxcharges ? `<span class="stat-tag">Charges: ${item.maxcharges}</span>` : ''}
            </div>
            <div class="stats-group">
                ${item.origin ? `<span class="stat-tag origin">Origin: ${formatOriginName(item.origin)}</span>` : ''}
                ${item.flag ? `<span class="stat-tag flag ${item.flag.toLowerCase()}">Flag: ${item.flag}</span>` : ''}
            </div>
        </div>
        ` : ''}
    `;
    
    card.addEventListener('click', () => {
        showItemModal(key, item);
    });
    
    card.style.cursor = 'pointer';
    
    return card;
}

function formatPoolText(pools, lang) {
    if (!pools || pools.length === 0) {
        return lang === 'kr' ? '알 수 없음' : 'Unknown';
    }
    
    const poolMapping = {
        'ROOM_ANGEL': { kr: '천사방', en: 'Angel Room' },
        'ROOM_DEVIL': { kr: '악마방', en: 'Devil Room' },
        'ROOM_TREASURE': { kr: '보물방', en: 'Treasure Room' },
        'ROOM_SHOP': { kr: '상점', en: 'Shop' },
        'ROOM_SECRET': { kr: '비밀방', en: 'Secret Room' },
        'ROOM_ULTRASECRET': { kr: '초비밀방', en: 'Ultra Secret Room' },
        'ROOM_CURSE': { kr: '저주방', en: 'Curse Room' },
        'ROOM_BLACK_MARKET': { kr: '블랙마켓', en: 'Black Market' },
        'ROOM_CHEST': { kr: '상자방', en: 'Chest Room' },
        'ROOM_BOSS': { kr: '보스방', en: 'Boss Room' },
        'ROOM_MINIBOSS': { kr: '미니보스방', en: 'Mini Boss Room' }
    };
    
    return pools.map(pool => {
        if (typeof pool === 'string') {
            return poolMapping[pool] ? poolMapping[pool][lang] : pool;
        } else if (typeof pool === 'object') {
            const poolType = Object.keys(pool).find(key => key.startsWith('ROOM_'));
            if (poolType) {
                return poolMapping[poolType] ? poolMapping[poolType][lang] : poolType;
            }
        }
        return pool;
    }).join(', ');
}

function formatOriginName(origin) {
    if (!origin) return '';
    
    return origin
        .split('_')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}

function getFlagDescription(flag, lang) {
    const flagDescriptions = {
        'positive': {
            kr: '긍정적 플래그 - 마법의 소라고둥이 "긍정적인 대답"을 할 때 이 아이템을 얻을 수 있습니다',
            en: 'Positive flag - You can get this item when the Magic Conch answers "Positive"'
        },
        'neutral': {
            kr: '중립적 플래그 - 마법의 소라고둥이 "중립적인 대답"을 할 때 이 아이템을 얻을 수 있습니다',
            en: 'Neutral flag - You can get this item when the Magic Conch answers "Neutral"'
        },
        'negative': {
            kr: '부정적 플래그 - 마법의 소라고둥이 "부정적인 대답"을 할 때 이 아이템을 얻을 수 있습니다',
            en: 'Negative flag - You can get this item when the Magic Conch answers "Negative"'
        }
    };
    
    return flagDescriptions[flag] ? flagDescriptions[flag][lang] : '';
}

function showItemModal(key, item) {
    const displayLang = getDisplayLanguage();
    const itemName = getLocalizedText(item, 'names', displayLang) || 'Unknown';
    const itemDescription = getLocalizedText(item, 'descriptions', displayLang) || '';
    
    const isWorkingNow = item.quality === undefined;
    
    const qualityStars = !isWorkingNow ? '⭐'.repeat(item.quality || 3) : '';
    
    const poolText = !isWorkingNow ? formatPoolText(item.pools, displayLang) : '';
    
    const tagsText = !isWorkingNow ? (item.tags || 'offensive') : '';
    
    let effects = [];
    if (item.eids && item.eids[displayLang]) {
        effects = item.eids[displayLang];
    } else {
        effects = [itemDescription || '효과 정보 없음'];
    }
    
    const modalHTML = `
        <div class="modal" id="itemModal">
            <div class="modal-content">
                <span class="close" onclick="closeItemModal()">&times;</span>
                <div class="modal-header">
                    <div class="modal-image-container">
                        <img src="${item.gfx || `resources/gfx/items/collectibles/${key.toLowerCase()}.png`}" 
                             alt="${itemName}" 
                             class="modal-image" 
                             onerror="this.style.display='none'; this.nextElementSibling.style.display='flex';">
                        <div class="modal-fallback" style="display:none;">
                            <div class="modal-fallback-icon">🎯</div>
                            <div class="modal-fallback-text">${itemName}</div>
                        </div>
                    </div>
                    <div class="modal-info">
                        <h2>
                            ${itemName}
                            ${displayLang === 'kr' && item.names && item.names.en ? `<span class="english-name">(${item.names.en})</span>` : ''}
                        </h2>
                        ${!isWorkingNow ? `<span class="modal-type">${(item.type || 'passive').toUpperCase()}</span>` : ''}
                        ${!isWorkingNow ? `<div class="modal-quality-stars">${qualityStars}</div>` : ''}
                    </div>
                </div>
                
                <div class="modal-description">${itemDescription}</div>
                
                <div class="modal-effects">
                    <h3 data-kr="효과" data-en="Effects">효과</h3>
                    <ul class="modal-effect-list">
                        ${effects.map(effect => `<li>${effect}</li>`).join('')}
                    </ul>
                </div>
                
                ${item.flag ? `
                <div class="modal-flag-info">
                    <h3 data-kr="플래그 정보" data-en="Flag Information">플래그 정보</h3>
                    <p class="flag-description">${getFlagDescription(item.flag, displayLang)}</p>
                </div>
                ` : ''}
                
                ${!isWorkingNow ? `
                <div class="modal-stats">
                    <div class="stats-group">
                        <span class="modal-stat-tag">Pool: ${poolText}</span>
                        <span class="modal-stat-tag">Tags: ${tagsText}</span>
                        ${item.shopprice ? `<span class="modal-stat-tag">Shop: ${item.shopprice}$</span>` : ''}
                        ${item.devilprice ? `<span class="modal-stat-tag">Devil: ${item.devilprice}♥</span>` : ''}
                        ${item.maxcharges ? `<span class="modal-stat-tag">Charges: ${item.maxcharges}</span>` : ''}
                    </div>
                    <div class="stats-group">
                        ${item.origin ? `<span class="modal-stat-tag origin">Origin: ${formatOriginName(item.origin)}</span>` : ''}
                        ${item.flag ? `<span class="modal-stat-tag flag ${item.flag.toLowerCase()}">Flag: ${item.flag}</span>` : ''}
                    </div>
                </div>
                ` : ''}
            </div>
        </div>
    `;
    
    const existingModal = document.getElementById('itemModal');
    if (existingModal) {
        existingModal.remove();
    }
    
    document.body.insertAdjacentHTML('beforeend', modalHTML);
    
    const modal = document.getElementById('itemModal');
    modal.style.display = 'block';
    
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            closeItemModal();
        }
    });
    
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            closeItemModal();
        }
    });
    
    updateModalContent(displayLang);
}

function closeItemModal() {
    const modal = document.getElementById('itemModal');
    if (modal) {
        modal.remove();
    }
}

function updateModalContent(lang) {
    const modal = document.getElementById('itemModal');
    if (!modal) return;
    
    modal.querySelectorAll('[data-kr][data-en]').forEach(element => {
        element.textContent = element.getAttribute(`data-${lang}`);
    });
}

document.addEventListener('DOMContentLoaded', function() {
    console.log('Conch\'s Blessing 아이템 가이드가 로드되었습니다!');
    
    initializeLanguage();
    
    const languageSelect = document.getElementById('languageSelect');
    if (languageSelect) {
        languageSelect.addEventListener('change', function() {
            const selectedLang = this.value;
            changeLanguage(selectedLang);
        });
    }
    
    initializeSearchAndFilter();
    
    updatePageContent();
    
    console.log('총 아이템 수:', typeof items !== 'undefined' ? Object.keys(items).length : 'N/A');
    console.log('현재 언어:', currentLanguage);
    console.log('감지된 언어:', detectedLanguage);
    console.log('표시 언어:', getDisplayLanguage());
});

window.ConchBlessing = {
    changeLanguage: changeLanguage,
    getCurrentLanguage: () => currentLanguage,
    getDisplayLanguage: getDisplayLanguage
}; 