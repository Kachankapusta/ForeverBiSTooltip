local _, ns = ...

local markers = {}
local initialized = false
local specIcons = {
    ["balance-druid"] = "Spell_Nature_StarFall",
    ["feral-tank-druid"] = "Ability_Racial_BearForm",
    ["feral-dps-druid"] = "Ability_Druid_CatForm",
    ["restoration-druid"] = "Spell_Nature_HealingTouch",
    ["beast-mastery-hunter"] = "Ability_Hunter_BeastTaming",
    ["marksmanship-hunter"] = "Ability_Marksmanship",
    ["survival-hunter"] = "Ability_Hunter_SwiftStrike",
    ["survival-melee-hunter"] = "ability_hunter_pet_tallstrider",
    ["arcane-mage"] = "Spell_Holy_MagicalSentry",
    ["fire-mage"] = "Spell_Fire_FireBolt02",
    ["frost-mage"] = "Spell_Frost_FrostBolt02",
    ["holy-paladin"] = "Spell_Holy_HolyBolt",
    ["protection-paladin"] = "Spell_Holy_DevotionAura",
    ["retribution-paladin"] = "Spell_Holy_AuraOfLight",
    ["shockadin-paladin"] = "Spell_Holy_SearingLight",
    ["discipline-priest"] = "Spell_Holy_WordFortitude",
    ["holy-priest"] = "Spell_Holy_Renew",
    ["shadow-priest"] = "Spell_Shadow_ShadowWordPain",
    ["assassination-rogue"] = "Ability_Rogue_Eviscerate",
    ["combat-rogue"] = "Ability_BackStab",
    ["subtlety-rogue"] = "Ability_Stealth",
    ["elemental-shaman"] = "Spell_Nature_Lightning",
    ["enhancement-shaman"] = "Spell_Nature_LightningShield",
    ["restoration-shaman"] = "Spell_Nature_MagicImmunity",
    ["affliction-warlock"] = "Spell_Shadow_DeathCoil",
    ["demonology-warlock"] = "Spell_Shadow_Metamorphosis",
    ["destruction-warlock"] = "Spell_Shadow_RainOfFire",
    ["arms-warrior"] = "Ability_Warrior_SavageBlow",
    ["fury-warrior"] = "Ability_Warrior_InnerRage",
    ["protection-warrior"] = "INV_Shield_06",
}

local function Icon(texture)
    if not texture then return "" end
    return "|TInterface\\Icons\\" .. texture .. ":14:14|t "
end

local function ClassIcon(classToken)
    local atlas = "classicon-" .. classToken:lower()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return "|A:" .. atlas .. ":14:14|a "
    end
    return Icon("ClassIcon_" .. classToken:sub(1, 1) .. classToken:sub(2):lower())
end

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

local function Spacer(width)
    width = math.floor(width + 0.5)
    if width < 1 then return "" end
    return "|TInterface\\Common\\Spacer:1:" .. width .. "|t"
end

local specIndent = Spacer(18)

local function LineFont(tooltip, side, lineNumber)
    local name = tooltip:GetName()
    if Secret(name) or type(name) ~= "string" then return end
    return _G[name .. "Text" .. side .. lineNumber]
end

local function TextWidth(font, text)
    if font and font.GetUnboundedStringWidthForText then
        local width = font:GetUnboundedStringWidthForText(text)
        if not Secret(width) and type(width) == "number" then return width end
    end
    return 0
end

local function ItemID(tooltip, data)
    if not Secret(data) and type(data) == "table" then
        local id = data.id
        if not Secret(id) and type(id) == "number" and id > 0 then
            return id
        end
    end

    if not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    if Secret(link) or type(link) ~= "string" then return end
    return tonumber(link:match("item:(%d+)"))
end

local function HasSection(tooltip, itemID)
    local marker = markers[tooltip]
    if not marker or marker.id ~= itemID then return false end

    local count = tooltip:NumLines()
    if Secret(count) or type(count) ~= "number" or count < marker.line then return false end

    local line = LineFont(tooltip, "Left", marker.line)
    if not line or not line.GetText then return false end
    local text = line:GetText()
    return not Secret(text) and text == marker.header
end

local function AddSection(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not ns.db or not ns.char or not ns.db.tooltip then return end
    if ns.db.ctrlOnly and not IsControlKeyDown() then return end

    local itemID = ItemID(tooltip, data)
    if not itemID or HasSection(tooltip, itemID) then return end
    local matches = ns.GetMatches(itemID)
    if not matches or #matches == 0 then return end

    local lineCount = tooltip:NumLines()
    if Secret(lineCount) or type(lineCount) ~= "number" then return end
    local header = "Forever BiS"
    local stage = ns.GetStageLabel(ns.char.stage)
    if ns.char.realistic then stage = stage .. " · " .. ns.L["Realistic"] end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(header, stage, 0.98, 0.79, 0.36, 0.98, 0.79, 0.36)
    markers[tooltip] = { id = itemID, line = lineCount + 2, header = header }

    local groups, byClass, rankWidths = {}, {}, {}
    local rankFont = LineFont(tooltip, "Right", lineCount + 2)
    local maxRankWidth = 0
    for _, match in ipairs(matches) do
        local class = match.spec.class
        local group = byClass[class]
        if not group then
            group = { class = class, matches = {} }
            groups[#groups + 1] = group
            byClass[class] = group
        end
        group.matches[#group.matches + 1] = match
        if not rankWidths[match.rank] then
            local width = TextWidth(rankFont, tostring(match.rank))
            rankWidths[match.rank] = width
            maxRankWidth = math.max(maxRankWidth, width)
        end
    end

    for _, group in ipairs(groups) do
        local class = group.class
        local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
        tooltip:AddLine(ClassIcon(class) .. name, 0.98, 0.79, 0.36)
        for _, match in ipairs(group.matches) do
            local spec = match.spec
            local left = specIndent .. Icon(specIcons[spec.id]) .. ns.L[spec.label]
            local right = "Top " .. Spacer(maxRankWidth - rankWidths[match.rank]) .. match.rank
            local r, g, b = 0.96, 0.88, 0.68
            if spec.id == ns.char.spec then r, g, b = 0.3, 1, 0.4 end
            tooltip:AddDoubleLine(left, right, r, g, b, r, g, b)
        end
    end

    local state = ns.GetItemState(itemID)
    if state == "equipped" then
        tooltip:AddLine(ns.L["Equipped"], 0.3, 1, 0.4)
    elseif state == "bags" then
        tooltip:AddLine(ns.L["In bags"], 0.3, 1, 0.4)
    end
    tooltip:Show()
end

function ns.RefreshTooltips()
    if not initialized then return end
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        if not (tooltip.IsForbidden and tooltip:IsForbidden()) and tooltip:IsShown() and ItemID(tooltip) then
            markers[tooltip] = nil
            if tooltip.RebuildFromTooltipInfo then
                tooltip:RebuildFromTooltipInfo()
            else
                tooltip:Hide()
            end
        end
    end
end

function ns.InitTooltip()
    if initialized then return end
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall
        or not Enum or not Enum.TooltipDataType then return end

    initialized = true
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
        tooltip:HookScript("OnTooltipCleared", function(self)
            markers[self] = nil
        end)
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddSection)
end
