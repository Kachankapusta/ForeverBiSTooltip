local _, ns = ...

local L = ns.L
local window, popup, minimapButton, sourceDialog
local settingsCategory
local rows, menuButtons = {}, {}
local rendering, sourcesInitialized = false, false
local equipmentPage, pageCount = 1, 1
local WIDTH, HEIGHT = 540, 660
local MIN_WIDTH, MIN_HEIGHT = 400, 400
local ICON_SIZE, ROW_HEIGHT = 40, 50
local ICON_GAP = 6
local SCROLL_LEFT, SCROLL_RIGHT = 20, 38
local SLOT_WIDTH, ENHANCEMENT_WIDTH = 128, 40
local GRID_X = SLOT_WIDTH + ENHANCEMENT_WIDTH + 10
local FRAME_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
}
local PANE_BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BUTTON_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

local function Skin(frame)
    frame:SetBackdrop(PANE_BACKDROP)
    frame:SetBackdropColor(0.11, 0.076, 0.05, 0.99)
    frame:SetBackdropBorderColor(0.67, 0.46, 0.28, 1)
end

local function Text(parent, template, size)
    local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    text:SetJustifyH("LEFT")
    if size then text:SetFont(STANDARD_TEXT_FONT, size, "") end
    return text
end

local function TextWidth(text)
    return math.ceil(text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth())
end

local function CloseMenu()
    if popup then popup:Hide() end
end

local function Button(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height or 24)
    button:SetBackdrop(BUTTON_BACKDROP)
    button:SetBackdropColor(0.20, 0.125, 0.074, 1)
    button:SetBackdropBorderColor(0.50, 0.34, 0.20, 1)
    button.label = Text(button, "GameFontNormal", 13)
    button.label:SetPoint("CENTER")
    button.label:SetText(label)
    button.label:SetTextColor(0.94, 0.80, 0.60)
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
    button:GetHighlightTexture():SetVertexColor(0.43, 0.29, 0.14, 0.24)
    button:SetScript("OnDisable", function(self) self.label:SetAlpha(0.42) end)
    button:SetScript("OnEnable", function(self) self.label:SetAlpha(1) end)
    return button
end

local function ShowMenu(owner, choices, selected, choose)
    if sourceDialog then sourceDialog:Hide() end
    if popup and popup.owner == owner and popup:IsShown() then popup:Hide(); return end
    if not popup then
        popup = CreateFrame("Frame", nil, window, "BackdropTemplate")
        popup:SetFrameStrata("DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        Skin(popup)
    end
    popup.owner = owner
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -1)
    local width = owner:GetWidth()
    popup:SetHeight(#choices * 26 + 8)
    popup:SetFrameLevel(window:GetFrameLevel() + 20)
    for i, choice in ipairs(choices) do
        local option = menuButtons[i]
        if not option then
            option = CreateFrame("Button", nil, popup)
            option:SetHeight(26)
            option:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            option.label = Text(option, nil, 13)
            option.label:SetPoint("LEFT", 9, 0)
            option.label:SetPoint("RIGHT", -9, 0)
            option.label:SetWordWrap(false)
            menuButtons[i] = option
        end
        option:ClearAllPoints()
        option:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 26)
        option:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4 - (i - 1) * 26)
        option.label:SetText(choice.label)
        width = math.max(width, TextWidth(option.label) + 26)
        if choice.id == selected then
            option.label:SetTextColor(1, 0.78, 0.43)
        else
            option.label:SetTextColor(0.92, 0.85, 0.74)
        end
        local selectedID = choice.id
        option:SetScript("OnClick", function() popup:Hide(); choose(selectedID) end)
        option:Show()
    end
    for i = #choices + 1, #menuButtons do menuButtons[i]:Hide() end
    popup:SetWidth(width)
    popup:Show()
end

local function Selector(parent, width, onClick)
    local selector = CreateFrame("Button", nil, parent, "BackdropTemplate")
    selector:SetSize(width, 28)
    Skin(selector)
    selector.label = Text(selector, nil, 13)
    selector.label:SetPoint("LEFT", 9, 0)
    selector.label:SetPoint("RIGHT", -26, 0)
    selector.label:SetWordWrap(false)
    local arrow = selector:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetSize(20, 20)
    arrow:SetPoint("RIGHT", -3, 0)
    selector:SetScript("OnClick", onClick)
    return selector
end

local function FitSelector(selector, measure, choices, localized)
    local width = selector:GetWidth()
    for _, choice in pairs(choices) do
        measure:SetText(localized and choice.label or L[choice.label])
        width = math.max(width, TextWidth(measure) + 39)
    end
    selector:SetWidth(width)
end

local function RealisticToggle(parent, onClick)
    local button = CreateFrame("Button", nil, parent)
    button.track = CreateFrame("Frame", nil, button, "BackdropTemplate")
    button.track:SetSize(34, 18)
    button.track:SetPoint("LEFT")
    button.track:SetBackdrop(BUTTON_BACKDROP)
    button.track:SetBackdropBorderColor(0.50, 0.34, 0.20, 1)
    button.thumb = button.track:CreateTexture(nil, "ARTWORK")
    button.thumb:SetSize(12, 12)
    local label = Text(button, nil, 13)
    label:SetText(L["Realistic"])
    label:SetPoint("LEFT", button.track, "RIGHT", 6, 0)
    button:SetSize(42 + TextWidth(label), 28)
    button:SetScript("OnClick", onClick)
    return button
end

local function UpdateRealisticToggle()
    local toggle = window.realistic
    local available = ns.HasRealistic()
    toggle:SetShown(available)
    if not available then return end

    toggle.thumb:ClearAllPoints()
    if ns.char.realistic then
        toggle.thumb:SetPoint("RIGHT", -3, 0)
        toggle.thumb:SetColorTexture(0.96, 0.76, 0.45, 1)
        toggle.track:SetBackdropColor(0.52, 0.31, 0.14, 1)
    else
        toggle.thumb:SetPoint("LEFT", 3, 0)
        toggle.thumb:SetColorTexture(0.62, 0.53, 0.43, 1)
        toggle.track:SetBackdropColor(0.13, 0.10, 0.075, 1)
    end
end

local function ShowSource()
    CloseMenu()
    if not sourceDialog then
        sourceDialog = CreateFrame("Frame", "ForeverBiSTooltipSourceDialog", window, "BackdropTemplate")
        sourceDialog:SetSize(650, 134)
        sourceDialog:SetClampedToScreen(true)
        sourceDialog:SetPoint("CENTER")
        sourceDialog:SetFrameStrata("DIALOG")
        sourceDialog:SetFrameLevel(window:GetFrameLevel() + 30)
        sourceDialog:EnableMouse(true)
        Skin(sourceDialog)
        local title = Text(sourceDialog, "GameFontNormal")
        title:SetPoint("TOPLEFT", 18, -15)
        title:SetText(L["Source page"])
        local close = CreateFrame("Button", nil, sourceDialog, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() sourceDialog:Hide() end)
        local edit = CreateFrame("EditBox", nil, sourceDialog, "InputBoxTemplate")
        edit:SetSize(605, 28)
        edit:SetPoint("TOPLEFT", 22, -47)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() sourceDialog:Hide() end)
        edit:SetScript("OnEnterPressed", function() sourceDialog:Hide() end)
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(self.sourceURL or "")
                self:HighlightText()
            end
        end)
        sourceDialog.edit = edit
        sourceDialog:SetScript("OnHide", function() edit:ClearFocus() end)
        local hint = Text(sourceDialog)
        hint:SetPoint("TOPLEFT", 18, -93)
        hint:SetText(L["Press Ctrl+C to copy the link."])
        hint:SetTextColor(0.65, 0.7, 0.78)
    end
    sourceDialog.edit.sourceURL = ns.GetSourceURL()
    sourceDialog.edit:SetText(sourceDialog.edit.sourceURL)
    sourceDialog:Show()
    sourceDialog.edit:SetFocus()
    sourceDialog.edit:HighlightText()
end

local function PublicText(value)
    if issecretvalue and issecretvalue(value) then return end
    if type(value) == "string" and value ~= "" then return value end
end

local function AddMaterials(tooltip, heading, materials, gold)
    if (not materials or #materials == 0) and not gold then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(L[heading], 0.98, 0.78, 0.46)
    for _, material in ipairs(materials or {}) do
        local name
        if material.id and C_Item and C_Item.GetItemNameByID then
            name = PublicText(C_Item.GetItemNameByID(material.id))
        end
        tooltip:AddDoubleLine(name or material.name, "×" .. material.count, 0.92, 0.86, 0.76, 1, 1, 1)
    end
    if gold then tooltip:AddLine(L["%d gold"]:format(gold), 0.98, 0.78, 0.46) end
end

local function AddEnhancementDetails(tooltip, entry, isEnchant)
    local effect = PublicText(entry.effect)
    local spellID = entry.spellID or (entry.kind == "spell" and entry.id)
    if not effect and spellID and C_Spell and C_Spell.GetSpellDescription then
        effect = PublicText(C_Spell.GetSpellDescription(spellID))
    end
    if effect then tooltip:AddLine(effect, 0.50, 0.88, 0.57, true) end
    AddMaterials(tooltip, "Crafting materials", entry.reagents)
    AddMaterials(tooltip, "Exchange requirements", entry.requirements, entry.requiredGold)
    if entry.tools and #entry.tools > 0 then
        tooltip:AddLine(L["Tools"] .. ": " .. table.concat(entry.tools, ", "), 0.83, 0.76, 0.65, true)
    end
    if isEnchant and not entry.reagents and not entry.requirements and not entry.requiredGold then
        tooltip:AddLine(L["Materials not listed"], 0.73, 0.67, 0.58, true)
    end
    if entry.source and entry.source ~= "" then
        tooltip:AddLine(" ")
        tooltip:AddLine(L["Source"] .. ": " .. entry.source, 0.92, 0.86, 0.76, true)
    end
    if entry.zone and entry.zone ~= "" then
        tooltip:AddLine(entry.zone, 0.74, 0.68, 0.58, true)
    end
    tooltip:AddLine(" ")
    if ns.CanShopForEnhancement(entry, not isEnchant) then
        tooltip:AddLine(L["Left-click to add to shopping. Right-click to remove."], 0.81, 0.76, 0.65, true)
    end
    tooltip:AddLine(L["Shift-left-click to inspect."], 0.81, 0.76, 0.65, true)
end

local function ItemDetails(tooltip, data)
    if tooltip ~= GameTooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if (issecretvalue and issecretvalue(data)) or type(data) ~= "table" then return end
    local owner = tooltip:GetOwner()
    if not owner or not owner.fbtGridItem then return end
    local id = data and data.id
    if (issecretvalue and issecretvalue(id)) or type(id) ~= "number" or id ~= owner.itemID then return end
    if tooltip.fbtSourceItem == id then return end
    tooltip.fbtSourceItem = id
    if owner.enhancement then
        AddEnhancementDetails(tooltip, owner.enhancement, false)
        return
    end
    local item = ns.Items[id] or {}
    if (not item.source or item.source == "") and (not item.sourceType or item.sourceType == "") then return end
    tooltip:AddLine(" ")
    if item.source and item.source ~= "" then tooltip:AddLine(L["Source"] .. ": " .. item.source, 1, 1, 1, true) end
    if item.sourceType and item.sourceType ~= "" then tooltip:AddLine(item.sourceType, 0.8, 0.8, 0.8, true) end
end

local function InitItemSources()
    if sourcesInitialized or not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall
        or not Enum or not Enum.TooltipDataType then return end
    sourcesInitialized = true
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip) tooltip.fbtSourceItem = nil end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ItemDetails)
end

local function ItemEnter(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.recommendationLabel == "Enchant" then
        local entry = self.enhancement
        local spellID = entry.spellID or (entry.kind == "spell" and entry.id)
        if entry.recipeItemID then ns.GetItemDisplay(entry.recipeItemID) end
        local name
        if entry.itemID and C_Item and C_Item.GetItemNameByID then
            name = PublicText(C_Item.GetItemNameByID(entry.itemID))
        elseif spellID and C_Spell and C_Spell.GetSpellName then
            name = PublicText(C_Spell.GetSpellName(spellID))
        end
        GameTooltip:SetText(name or entry.name, 1, 0.82, 0.5)
        AddEnhancementDetails(GameTooltip, entry, true)
    elseif self.kind == "spell" then
        GameTooltip:SetSpellByID(self.itemID)
    else
        GameTooltip:SetItemByID(self.itemID)
    end
    GameTooltip:Show()
end

local function ItemClick(self, button)
    if not self.itemID then return end
    CloseMenu()
    local entry = self.enhancement
    if entry and not IsModifierKeyDown() then
        if button == "LeftButton" then
            ns.ShopForEnhancement(entry, self.recommendationLabel == "Gems")
        elseif button == "RightButton" then
            ns.RemoveShoppingEnhancement(entry)
        end
        return
    end
    if button == "RightButton" then return end
    if entry and IsShiftKeyDown() then
        local kind = entry.recipeItemID and "item" or self.kind
        local id = entry.recipeItemID or (kind == "spell" and entry.spellID) or self.itemID
        ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
        ItemRefTooltip:SetHyperlink(kind .. ":" .. id)
        ItemRefTooltip:Show()
        return
    end
    local link
    if entry and entry.recipeItemID and not IsModifiedClick("CHATLINK") then
        link = ns.GetItemDisplay(entry.recipeItemID).link
    end
    if not link and self.kind == "item" then
        link = ns.GetItemDisplay(self.itemID).link
    elseif not link and (self.kind == "spell" or (entry and entry.spellID)) then
        local spellID = entry and entry.spellID or self.itemID
        link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(spellID)
    end
    link = PublicText(link)
    if not link then return end
    if not HandleModifiedItemClick(link) then
        local hyperlink = link:match("|H([^|]+)|h")
        if hyperlink then SetItemRef(hyperlink, link, "LeftButton") end
    end
end

local function IconButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetAllPoints()
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    button.check = button:CreateTexture(nil, "OVERLAY")
    button.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    button.check:SetSize(math.min(size, 16), math.min(size, 16))
    button.check:SetPoint("BOTTOMRIGHT", 2, -2)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnEnter", ItemEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", ItemClick)
    return button
end

local function ConfigureIcon(button, entry, kind, recommendationLabel)
    if not entry then button.itemID = nil; button:Hide(); return end
    button.itemID, button.kind = entry.itemID or entry.id, kind
    button.preferred, button.recommendationLabel = entry.preferred == true, recommendationLabel
    button.enhancement = recommendationLabel and entry or nil
    button.fbtGridItem = kind == "item"
    local icon, color
    if kind == "spell" or recommendationLabel == "Enchant" then
        local spellID = entry.spellID or (kind == "spell" and entry.id)
        icon = entry.icon and ("Interface\\Icons\\" .. entry.icon)
        if not icon and spellID and C_Spell and C_Spell.GetSpellTexture then
            icon = C_Spell.GetSpellTexture(spellID)
            if issecretvalue and issecretvalue(icon) then icon = nil end
        end
        color = { r = 0.74, g = 0.56, b = 0.38 }
    else
        local display = ns.GetItemDisplay(entry.id)
        icon, color = display.icon, display.color
    end
    button.icon:SetTexture(icon or "Interface\\Icons\\INV_Enchant_FormulaGood_01")
    if button.preferred then
        button.border:SetColorTexture(0.80, 0.61, 0.34, 1)
    else
        button.border:SetColorTexture(color.r * 0.70, color.g * 0.70, color.b * 0.70, 1)
    end
    button.check:SetShown(kind == "item" and recommendationLabel ~= "Enchant" and ns.GetItemState(entry.id) ~= nil)
    button:Show()
end

local function GetRow(index)
    local row = rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, window.content)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetColorTexture(0.58, 0.39, 0.22, 0.26)
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT")
    row.rule:SetPoint("BOTTOMRIGHT")
    row.slot = Text(row, nil, 14)
    row.slot:SetPoint("TOPLEFT", 4, -16)
    row.slot:SetWidth(SLOT_WIDTH - 8)
    row.slot:SetWordWrap(true)
    row.slot:SetMaxLines(2)
    row.slot:SetTextColor(0.93, 0.86, 0.75)
    row.items, row.enhancements = {}, {}
    row.emptyEnhancements = Text(row, nil, 13)
    row.emptyEnhancements:SetPoint("TOPLEFT", SLOT_WIDTH + 15, -17)
    row.emptyEnhancements:SetText("—")
    row.emptyEnhancements:SetTextColor(0.4, 0.4, 0.4)
    rows[index] = row
    return row
end

local function Enhancements(row, enchant, gems)
    local recommendations = {}
    if enchant then recommendations[#recommendations + 1] = { value = enchant, label = "Enchant" } end
    for _, gem in ipairs(gems or {}) do recommendations[#recommendations + 1] = { value = gem, label = "Gems" } end
    local height = math.max(ROW_HEIGHT, math.ceil(#recommendations / 2) * 20 + 8)
    for i, recommendation in ipairs(recommendations) do
        local button = row.enhancements[i]
        if not button then button = IconButton(row, 18); row.enhancements[i] = button end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", SLOT_WIDTH + ((i - 1) % 2) * 20, -6 - math.floor((i - 1) / 2) * 20)
        ConfigureIcon(button, recommendation.value, recommendation.value.kind or "item", recommendation.label)
    end
    for i = #recommendations + 1, #row.enhancements do row.enhancements[i]:Hide() end
    row.emptyEnhancements:SetShown(#recommendations == 0)
    return height
end

local function LayoutToolbar()
    local left, right = SCROLL_LEFT, window:GetWidth() - 20
    local gap, rowHeight = 7, 28
    local x, y = left, 38
    local selectors = { window.classSelector, window.specSelector, window.stageSelector }
    if window.realistic:IsShown() then selectors[#selectors + 1] = window.realistic end
    for _, control in ipairs(selectors) do
        local width = control:GetWidth()
        if x > left and x + width > right then
            x = left
            y = y + rowHeight + gap
        end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", x, -y)
        x = x + width + gap
    end
    local headerY = y + rowHeight + 9
    window.header:ClearAllPoints()
    window.header:SetPoint("TOPLEFT", SCROLL_LEFT, -headerY)
    window.header:SetPoint("TOPRIGHT", -SCROLL_RIGHT, -headerY)
end

local function Render()
    if rendering or not window or not window:IsShown() then return end
    rendering = true
    local selected = ns.GetSpec(ns.char.spec)
    if selected then
        for _, class in ipairs(ns.Classes) do
            if class.id == selected.class then window.classSelector.label:SetText(L[class.label]); break end
        end
        window.specSelector.label:SetText(L[selected.label])
    end
    window.stageSelector.label:SetText(ns.GetStageLabel(ns.char.stage))
    local hasStages = #ns.GetStages(ns.char.spec) > 1
    window.stageSelector:SetEnabled(hasStages)
    window.stageSelector:SetAlpha(hasStages and 1 or 0.7)
    UpdateRealisticToggle()
    LayoutToolbar()
    local list = ns.GetList()
    local visibleRows, maxEntries = {}, 0
    for _, slot in ipairs(ns.Slots) do
        local entries = list and list.slots[slot.id]
        if entries and #entries > 0 then
            visibleRows[#visibleRows + 1] = { slot = slot.id, entries = ns.OrderedEntries(entries) }
            maxEntries = math.max(maxEntries, #entries)
        end
    end
    local contentWidth = window:GetWidth() - SCROLL_LEFT - SCROLL_RIGHT
    window.content:SetWidth(contentWidth)
    local step = ICON_SIZE + ICON_GAP
    local columns = math.max(1, math.floor((contentWidth - GRID_X + ICON_GAP) / step))
    pageCount = math.max(1, math.ceil(maxEntries / columns))
    equipmentPage = math.min(equipmentPage, pageCount)
    local firstEntry = (equipmentPage - 1) * columns + 1
    local visibleColumns = math.min(columns, maxEntries - firstEntry + 1)
    local firstAlternativeColumn = equipmentPage == 1 and 2 or 1
    window.mainHeader:SetShown(equipmentPage == 1 and visibleColumns > 0)
    local showAlternatives = visibleColumns >= firstAlternativeColumn
    window.alternativesHeader:SetShown(showAlternatives)
    if showAlternatives then
        local x = GRID_X + step * (firstAlternativeColumn - 1)
        local lastColumn = math.min(columns, maxEntries)
        local span = ICON_SIZE + step * (lastColumn - firstAlternativeColumn)
        local width = math.min(contentWidth - x, math.max(span, TextWidth(window.alternativesHeader)))
        window.alternativesHeader:ClearAllPoints()
        window.alternativesHeader:SetPoint("LEFT", window.header, "LEFT", x, 0)
        window.alternativesHeader:SetWidth(width)
    end
    local y = 0
    for index, data in ipairs(visibleRows) do
        local row = GetRow(index)
        local enchant = list.enchants and list.enchants[data.slot]
        local gems = list.gems and list.gems[data.slot]
        local displayed = math.max(0, math.min(columns, #data.entries - firstEntry + 1))
        local height = Enhancements(row, enchant, gems)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -y)
        row:SetHeight(height)
        row.slot:SetText(ns.GetSlotLabel(data.slot))
        row.background:SetColorTexture(0.75, 0.50, 0.27, index % 2 == 0 and 0.065 or 0)
        for i = 1, displayed do
            local button = row.items[i]
            if not button then
                button = IconButton(row, ICON_SIZE)
                button:SetPoint("TOPLEFT", GRID_X + step * (i - 1), -5)
                row.items[i] = button
            end
            ConfigureIcon(button, data.entries[firstEntry + i - 1], "item")
        end
        for i = displayed + 1, #row.items do ConfigureIcon(row.items[i], nil, "item") end
        row:Show()
        y = y + height
    end
    for i = #visibleRows + 1, #rows do rows[i]:Hide() end
    window.empty:SetShown(#visibleRows == 0)
    window.content:SetHeight(math.max(y, 1))
    window.scroll:SetVerticalScroll(math.min(window.scroll:GetVerticalScroll(), math.max(0, y - window.scroll:GetHeight())))
    window.previous:SetShown(pageCount > 1)
    window.next:SetShown(pageCount > 1)
    window.pageLabel:SetShown(pageCount > 1)
    window.previous:SetEnabled(equipmentPage > 1)
    window.next:SetEnabled(equipmentPage < pageCount)
    window.pageLabel:SetText(equipmentPage .. " / " .. pageCount)
    window.footer:SetText(L["Updated"] .. ": " .. ns.Source.updated)
    rendering = false
end

local function ApplyWindowPosition(position)
    local width = type(position) == "table" and tonumber(position.width) or WIDTH
    local height = type(position) == "table" and tonumber(position.height) or HEIGHT
    window:ClearAllPoints()
    if type(position) == "table" and type(position.point) == "string" and type(position.relativePoint) == "string"
        and type(position.x) == "number" and type(position.y) == "number" then
        window:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else window:SetPoint("CENTER") end
    window:SetSize(math.max(MIN_WIDTH, math.min(width or WIDTH, UIParent:GetWidth() - 20)),
        math.max(MIN_HEIGHT, math.min(height or HEIGHT, UIParent:GetHeight() - 30)))
end

local function ResetMainWindow()
    ns.char.windowPosition = nil
    if not window then return end
    window:StopMovingOrSizing()
    window:SetUserPlaced(false)
    ApplyWindowPosition()
end

local function RegisterSetting(key, name, default, description, inverted)
    inverted = inverted == true
    local setting = Settings.RegisterProxySetting(settingsCategory, "ForeverBiSTooltip_" .. key, "boolean",
        L[name], default, function()
            return ns.db[key] ~= inverted
        end, function(value)
            ns.db[key] = value ~= inverted
            if key == "minimap" then
                if minimapButton then minimapButton:SetShown(ns.db.minimap) end
            elseif key == "shoppingMissingOnly" then
                ns.UpdateShoppingWindow()
            elseif key ~= "shoppingAutoOpen" and key ~= "shoppingCloseWithMain" then
                ns.Refresh()
            end
        end)
    Settings.CreateCheckbox(settingsCategory, setting, L[description])
end

local function RegisterRankSetting()
    if not Settings.CreateDropdown or not Settings.CreateControlTextContainer then return end
    local setting = Settings.RegisterProxySetting(settingsCategory, "ForeverBiSTooltip_tooltipMaxRank", "number",
        L["Ranks in tooltips"], 0, function()
            return ns.db.tooltipMaxRank
        end, function(value)
            ns.db.tooltipMaxRank = value
            ns.Refresh()
        end)
    Settings.CreateDropdown(settingsCategory, setting, function()
        local options = Settings.CreateControlTextContainer()
        options:Add(0, L["All ranks"])
        options:Add(1, L["Top 1"])
        options:Add(3, L["Top 3"])
        options:Add(5, L["Top 5"])
        return options:GetData()
    end, L["Choose which BiS ranks to show in item tooltips."])
end

local function AddSettingsHeading(layout, name)
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L[name]))
    end
end

local function RegisterSettings()
    if settingsCategory or not Settings or not Settings.RegisterVerticalLayoutCategory
        or not Settings.RegisterProxySetting or not Settings.CreateCheckbox
        or not Settings.RegisterAddOnCategory then return end

    local layout
    settingsCategory, layout = Settings.RegisterVerticalLayoutCategory("Forever BiS Tooltip")
    AddSettingsHeading(layout, "Tooltip")
    RegisterSetting("tooltip", "Show tooltip", true, "Adds BiS recommendations to item tooltips.")
    RegisterSetting("allSpecs", "Only selected spec", true,
        "Choose a specialization in the window; tooltip filtering follows this selection.", true)
    RegisterSetting("ctrlOnly", "Ctrl only", false, "Adds BiS recommendations only while Ctrl is held.")
    RegisterRankSetting()

    AddSettingsHeading(layout, "Shopping list")
    RegisterSetting("shoppingAutoOpen", "Automatically open the shopping list", true,
        "Opens the shopping list when you add an enchant or gem.")
    RegisterSetting("shoppingCloseWithMain", "Close the shopping list with the main window", true,
        "Also applies when the shopping list is moved separately.")
    RegisterSetting("shoppingMissingOnly", "Only missing reagents", false,
        "Hides reagents you already have enough of in the shopping list.")

    AddSettingsHeading(layout, "Windows")
    RegisterSetting("minimap", "Minimap button", true, "Shows the minimap button for BiS, shopping, and settings.")
    if layout and CreateSettingsButtonInitializer then
        layout:AddInitializer(CreateSettingsButtonInitializer(L["Main window"], L["Reset"], ResetMainWindow,
            L["Restores the default size and position of the main window."], true))
        layout:AddInitializer(CreateSettingsButtonInitializer(L["Shopping list"], L["Reset"], ns.ResetShoppingWindow,
            L["Restores the default shopping list size and docks it to the main window."], true))
    end
    Settings.RegisterAddOnCategory(settingsCategory)
end

local function OpenSettings()
    if not settingsCategory or not Settings.OpenToCategory or InCombatLockdown() then return end
    if window then window:Hide() end
    Settings.OpenToCategory(settingsCategory:GetID())
end

local function SaveWindowPosition()
    local point, _, relativePoint, x, y = window:GetPoint()
    ns.char.windowPosition = {
        point = point, relativePoint = relativePoint, x = x, y = y,
        width = window:GetWidth(), height = window:GetHeight(),
    }
end

local function ResetPage()
    equipmentPage = 1
    window.scroll:SetVerticalScroll(0)
end

local function CreateWindow()
    window = CreateFrame("Frame", "ForeverBiSTooltipFrame", UIParent, "BackdropTemplate")
    window:Hide()
    ApplyWindowPosition(ns.char.windowPosition)
    window:SetResizable(true)
    window:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, UIParent:GetWidth(), UIParent:GetHeight())
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetBackdrop(FRAME_BACKDROP)
    window:SetBackdropColor(0.105, 0.079, 0.060, 1)
    window:SetBackdropBorderColor(0.78, 0.58, 0.37, 1)
    window:SetScript("OnDragStart", function(self) CloseMenu(); self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveWindowPosition() end)
    window:SetScript("OnMouseDown", CloseMenu)
    window:SetScript("OnShow", Render)
    window:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        SaveWindowPosition()
        if ns.db.shoppingCloseWithMain ~= false then ns.CloseShoppingWindow() end
        CloseMenu()
        if sourceDialog then sourceDialog:Hide() end
        GameTooltip:Hide()
    end)
    UISpecialFrames[#UISpecialFrames + 1] = "ForeverBiSTooltipFrame"
    local titleBackground = window:CreateTexture(nil, "ARTWORK")
    titleBackground:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBackground:SetSize(260, 40)
    titleBackground:SetPoint("TOP", 0, 12)
    titleBackground:SetTexCoord(0.2, 0.8, 0, 0.63)
    titleBackground:SetVertexColor(0.89, 0.69, 0.45, 1)
    local title = Text(window, "GameFontNormal", 14)
    title:SetPoint("TOP", 0, -2)
    title:SetText("Forever BiS Tooltip")
    title:SetTextColor(0.98, 0.81, 0.56)

    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", -7, -5)
    close:SetScript("OnClick", function() window:Hide() end)
    local settings = CreateFrame("Button", nil, window)
    settings:SetSize(24, 24)
    settings:SetPoint("RIGHT", close, "LEFT", -4, 0)
    settings:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("OptionsIcon-Brown") then
        settings:GetNormalTexture():SetAtlas("OptionsIcon-Brown")
    end
    settings:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    settings:SetScript("OnClick", OpenSettings)
    settings:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Settings"])
        GameTooltip:Show()
    end)
    settings:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window.classSelector = Selector(window, 92, function(owner)
        local choices, selected = {}, ns.GetSpec(ns.char.spec)
        for _, class in ipairs(ns.Classes) do choices[#choices + 1] = { id = class.id, label = L[class.label] } end
        ShowMenu(owner, choices, selected and selected.class, function(classID)
            for _, spec in ipairs(ns.Specs) do
                if spec.class == classID then ResetPage(); ns.SelectSpec(spec.id); break end
            end
        end)
    end)
    window.stageSelector = Selector(window, 86, function(owner)
        local choices = {}
        for _, stage in ipairs(ns.GetStages(ns.char.spec)) do choices[#choices + 1] = { id = stage.id, label = ns.GetStageLabel(stage.id) } end
        ShowMenu(owner, choices, ns.char.stage, function(id) ResetPage(); ns.SelectStage(id) end)
    end)
    window.specSelector = Selector(window, 104, function(owner)
        local choices, selected = {}, ns.GetSpec(ns.char.spec)
        for _, spec in ipairs(ns.Specs) do
            if selected and spec.class == selected.class then choices[#choices + 1] = { id = spec.id, label = L[spec.label] } end
        end
        ShowMenu(owner, choices, ns.char.spec, function(id) ResetPage(); ns.SelectSpec(id) end)
    end)

    local measure = Text(window, nil, 13)
    measure:Hide()
    FitSelector(window.classSelector, measure, ns.Classes)
    FitSelector(window.specSelector, measure, ns.Specs)
    local phases = {}
    for _, spec in ipairs(ns.Specs) do
        for _, stage in ipairs(ns.GetStages(spec.id)) do
            phases[stage.id] = stage
        end
    end
    FitSelector(window.stageSelector, measure, phases, true)

    window.realistic = RealisticToggle(window, function()
        ResetPage()
        ns.SetRealistic(not ns.char.realistic)
    end)

    window.header = CreateFrame("Frame", nil, window)
    window.header:SetHeight(25)
    local headingRule = window.header:CreateTexture(nil, "ARTWORK")
    headingRule:SetColorTexture(0.69, 0.48, 0.28, 0.55)
    headingRule:SetPoint("BOTTOMLEFT")
    headingRule:SetPoint("BOTTOMRIGHT")
    headingRule:SetHeight(1)
    local slotHeader = Text(window.header, "GameFontNormal", 13)
    slotHeader:SetPoint("LEFT", 4, 0)
    slotHeader:SetWidth(46)
    slotHeader:SetWordWrap(false)
    slotHeader:SetText(L["Slot"])
    local enchantHeader = Text(window.header, "GameFontNormal", 13)
    enchantHeader:SetPoint("LEFT", slotHeader, "RIGHT", 6, 0)
    enchantHeader:SetPoint("RIGHT", window.header, "LEFT", SLOT_WIDTH + ENHANCEMENT_WIDTH, 0)
    enchantHeader:SetJustifyH("RIGHT")
    enchantHeader:SetWordWrap(false)
    enchantHeader:SetText(L["Enhancements"])
    window.mainHeader = Text(window.header, "GameFontNormal", 13)
    window.mainHeader:SetText(L["BiS"])
    window.mainHeader:SetWidth(ICON_SIZE)
    window.mainHeader:SetJustifyH("CENTER")
    window.mainHeader:SetPoint("CENTER", window.header, "LEFT", GRID_X + ICON_SIZE / 2, 0)
    window.alternativesHeader = Text(window.header, "GameFontNormal", 13)
    window.alternativesHeader:SetJustifyH("CENTER")
    window.alternativesHeader:SetWordWrap(false)
    window.alternativesHeader:SetText(L["Alternatives"])
    window.scroll = CreateFrame("ScrollFrame", "ForeverBiSTooltipScrollFrame", window, "UIPanelScrollFrameTemplate")
    window.scroll:SetPoint("TOPLEFT", window.header, "BOTTOMLEFT", 0, -4)
    window.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_RIGHT, 81)
    window.content = CreateFrame("Frame", nil, window.scroll)
    window.content:SetSize(WIDTH - SCROLL_LEFT - SCROLL_RIGHT, 1)
    window.scroll:SetScrollChild(window.content)
    window.empty = Text(window, "GameFontNormal", 14)
    window.empty:SetPoint("CENTER", window.scroll, "CENTER")
    window.empty:SetText(L["No list is available for this selection."])

    window.footer = Text(window, nil, 12)
    window.footer:SetPoint("BOTTOMLEFT", 23, 51)
    window.footer:SetTextColor(0.75, 0.75, 0.75)
    local source = Button(window, "wowtbc.gg", 105)
    source:SetPoint("BOTTOMLEFT", 20, 20)
    source:SetScript("OnClick", ShowSource)
    ns.InitShoppingUI(window, Text, Button, FRAME_BACKDROP, TextWidth)
    window.shoppingButton = Button(window, L["Shopping"], 104)
    window.shoppingButton:SetPoint("BOTTOMRIGHT", -22, 20)
    window.shoppingButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    window.shoppingButton:SetScript("OnClick", function(_, button)
        CloseMenu()
        if button == "RightButton" then
            ns.ResetShoppingWindow()
        else
            ns.ToggleShoppingWindow()
        end
    end)
    window.previous = Button(window, "<", 26)
    window.previous:SetPoint("BOTTOM", -56, 20)
    window.previous:SetScript("OnClick", function() CloseMenu(); equipmentPage = math.max(1, equipmentPage - 1); Render() end)
    window.next = Button(window, ">", 26)
    window.next:SetPoint("BOTTOM", 56, 20)
    window.next:SetScript("OnClick", function() CloseMenu(); equipmentPage = math.min(pageCount, equipmentPage + 1); Render() end)
    window.pageLabel = Text(window, nil, 13)
    window.pageLabel:SetPoint("BOTTOM", 0, 25)
    window.pageLabel:SetJustifyH("CENTER")
    local resize = CreateFrame("Button", nil, window)
    resize:SetSize(19, 19)
    resize:SetPoint("BOTTOMRIGHT", -2, 2)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then CloseMenu(); window:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp", function() window:StopMovingOrSizing(); SaveWindowPosition(); Render() end)
    window:HookScript("OnSizeChanged", function() CloseMenu(); Render() end)
end

local function PositionMinimapButton()
    if not minimapButton then return end
    local angle = math.rad(ns.db.minimapAngle or 225)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * (Minimap:GetWidth() / 2 + 5),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 5))
end

function ns.InitUI()
    ns.InitShoppingUI(nil, Text, Button, FRAME_BACKDROP, TextWidth)
    InitItemSources()
    RegisterSettings()
    if not Minimap or minimapButton then return end
    minimapButton = CreateFrame("Button", "ForeverBiSTooltipMinimapButton", Minimap)
    minimapButton:SetSize(31, 31)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = minimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    local icon = minimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_Vendor_GreenCabbage")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    minimapButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if not window then CreateWindow() end
            ns.ToggleShoppingWindow()
        elseif IsShiftKeyDown() then
            OpenSettings()
        else
            ns.ToggleUI()
        end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Forever BiS Tooltip")
        GameTooltip:AddLine(L["Left-click to open or close the BiS window."], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click to open or close the shopping list."], 1, 1, 1)
        GameTooltip:AddLine(L["Shift-left-click to open settings."], 1, 1, 1)
        GameTooltip:AddLine(L["Drag to move."], 0.65, 0.7, 0.8)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapButton:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(y / scale - my, x / scale - mx)) % 360
            PositionMinimapButton()
        end)
    end)
    minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    PositionMinimapButton()
    minimapButton:SetShown(ns.db.minimap ~= false)
end

function ns.ToggleUI()
    if not window then CreateWindow() end
    window:SetShown(not window:IsShown())
end

function ns.UIRefresh()
    Render()
end
