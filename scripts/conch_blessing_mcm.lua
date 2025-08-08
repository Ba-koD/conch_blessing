local ConchBlessing_MCM = {}

---@diagnostic disable-next-line: undefined-global
local ModConfigMenu = ModConfigMenu

function ConchBlessing_MCM.Setup(mod)
    if not ModConfigMenu then
        return
    end

    local ConchBlessing_Config = require("conch_blessing_config")
    local category = "Conch's Blessing v" .. tostring(mod.Config.Version or "")

    -- Recreate category to reflect any text changes
    ModConfigMenu.RemoveCategory(category)
    ModConfigMenu.AddSpace(category, "General")
    ModConfigMenu.AddText(category, "General", "--- Conch's Blessing Options ---")

    -- Language Selection (0: Auto, 1..N: languages from LANGUAGE_MAP)
    ModConfigMenu.AddSetting(category, "General", {
        Type = ModConfigMenu.OptionType.NUMBER,
        CurrentSetting = function()
            local lang = mod.Config.language
            if type(lang) == "string" and lang ~= "auto" and lang ~= "Auto" then
                for i, langObj in ipairs(ConchBlessing_Config.LANGUAGE_MAP) do
                    if langObj.code == lang then
                        return i
                    end
                end
            end
            return 0 -- 0: Auto
        end,
        Minimum = 0,
        Maximum = #ConchBlessing_Config.LANGUAGE_MAP,
        Display = function()
            local idx = 0
            local lang = mod.Config.language
            if type(lang) == "string" and lang ~= "auto" and lang ~= "Auto" then
                for i, langObj in ipairs(ConchBlessing_Config.LANGUAGE_MAP) do
                    if langObj.code == lang then
                        idx = i
                        break
                    end
                end
            end
            if idx == 0 then
                local code = ConchBlessing_Config.GetCurrentLanguage(mod)
                local name = code
                for _, l in ipairs(ConchBlessing_Config.LANGUAGE_MAP) do
                    if l.code == code then
                        name = l.name or code
                        break
                    end
                end
                return "Language: Auto(" .. tostring(name) .. ")"
            else
                local langObj = ConchBlessing_Config.LANGUAGE_MAP[idx]
                return "Language: " .. tostring(langObj.name or langObj.code)
            end
        end,
        OnChange = function(n)
            if n == 0 then
                mod.Config.language = "auto"
            else
                local langObj = ConchBlessing_Config.LANGUAGE_MAP[n]
                if langObj then
                    mod.Config.language = langObj.code
                end
            end
            ConchBlessing_Config.Save(mod)
            -- Re-register EID strings to reflect new language immediately
            if mod.EID and type(mod.EID.registerAllItems) == "function" then
                mod.EID.registerAllItems()
            end
            -- Also refresh HUD next pickup via config-aware resolver
        end,
        Info = {"Select the output language.", "(Default: Auto uses game language)"},
    })
end

return ConchBlessing_MCM

