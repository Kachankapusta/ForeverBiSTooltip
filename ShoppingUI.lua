local _, ns = ...

local L = ns.L
local Text, Button, frameBackdrop, TextWidth
local panel, mainWindow, auctionButton
local materialRows, entryRows = {}, {}
local hookedAuctions = {}
local WIDTH, HEIGHT = 490, 470
local MIN_WIDTH, MIN_HEIGHT = 320, 240
local SCROLL_LEFT, SCROLL_RIGHT = 20, 38
local ROW_INSET, NAME_GAP = 3, 7
local MATERIAL_AMOUNT_WIDTH = 128
local QUANTITY_BUTTON_WIDTH, QUANTITY_GAP = 22, 8
local MATERIAL_RESERVED_WIDTH = 2 * ROW_INSET + NAME_GAP + MATERIAL_AMOUNT_WIDTH
local ENTRY_RESERVED_WIDTH = 2 * (ROW_INSET + QUANTITY_BUTTON_WIDTH + QUANTITY_GAP) + NAME_GAP

local function AuctionTabOffset(auction)
    local offset = 52
    if auction == AuctionHouseFrame and C_AddOns then
        if C_AddOns.IsAddOnLoaded("AllTheThings") then offset = offset + 62 end
        if C_AddOns.IsAddOnLoaded("ProfessionShoppingList") then offset = offset + 62 end
    end
    return offset
end

local function UpdateAuctionTab()
    if not auctionButton then return end
    local auction = auctionButton:GetParent()
    local selected = panel ~= nil and panel.auction == auction and panel:IsShown()
    auctionButton:SetChecked(selected)
    auctionButton:ClearAllPoints()
    auctionButton:SetPoint("TOPLEFT", selected and panel or auction, "TOPRIGHT", -2, -AuctionTabOffset(auction))
end

local function PositionRow(row, y, height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -y)
    row:SetPoint("TOPRIGHT", panel.content, "TOPRIGHT", 0, -y)
    row:SetHeight(height)
    row:Show()
end

local function ShowRowTooltip(row, link)
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

local function HideRowTooltip(row)
    if GameTooltip:GetOwner() == row then GameTooltip:Hide() end
end

local function CreateLinkRow()
    local row = CreateFrame("Frame", nil, panel.content, "InlineHyperlinkFrameTemplate")
    row:EnableMouse(true)
    row:SetHyperlinksEnabled(true)
    row:SetScript("OnHyperlinkEnter", ShowRowTooltip)
    row:SetScript("OnHyperlinkLeave", HideRowTooltip)
    row:SetScript("OnHide", HideRowTooltip)
    return row
end

local function SetRowName(row, text)
    if row.name:GetText() == text then return end
    HideRowTooltip(row)
    row.name:SetText(text)
end

local function GetMaterialRow(index)
    local row = materialRows[index]
    if row then return row end
    row = CreateLinkRow()
    materialRows[index] = row
    row.amount = Text(row, nil, 13)
    row.amount:SetPoint("TOPRIGHT", -ROW_INSET, -3)
    row.amount:SetWidth(MATERIAL_AMOUNT_WIDTH)
    row.amount:SetJustifyH("RIGHT")
    row.name = Text(row, nil, 13)
    row.name:SetPoint("TOPLEFT", ROW_INSET, -3)
    row.name:SetPoint("TOPRIGHT", row.amount, "TOPLEFT", -NAME_GAP, 0)
    row.name:SetWordWrap(false)
    row.binding = Text(row, nil, 11)
    row.binding:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
    row.binding:SetTextColor(0.77, 0.66, 0.52)
    row.binding:SetText(L["Unavailable at the auction house"])
    return row
end

local function GetEntryRow(index)
    local row = entryRows[index]
    if row then return row end
    row = CreateLinkRow()
    entryRows[index] = row
    row.add = Button(row, "+", QUANTITY_BUTTON_WIDTH, 21)
    row.add:SetPoint("RIGHT", -ROW_INSET, 0)
    row.add:SetScript("OnClick", function() ns.IncreaseShoppingEntry(row.key) end)
    row.amount = Text(row, nil, 13)
    row.amount:SetPoint("RIGHT", row.add, "LEFT", -QUANTITY_GAP, 0)
    row.remove = Button(row, "−", QUANTITY_BUTTON_WIDTH, 21)
    row.remove:SetPoint("RIGHT", row.amount, "LEFT", -QUANTITY_GAP, 0)
    row.remove:SetScript("OnClick", function() ns.RemoveShoppingEntry(row.key) end)
    row.name = Text(row, nil, 13)
    row.name:SetPoint("LEFT", ROW_INSET, 0)
    row.name:SetPoint("RIGHT", row.remove, "LEFT", -NAME_GAP, 0)
    row.name:SetWordWrap(false)
    return row
end

local function QuantityText(quantity, isGold)
    if quantity == nil then return "—" end
    if isGold then quantity = math.floor(quantity) end
    return tostring(quantity)
end

local function ClampScroll()
    local maxScroll = math.max(0, panel.content:GetHeight() - panel.scroll:GetHeight())
    if panel.scroll:GetVerticalScroll() > maxScroll then panel.scroll:SetVerticalScroll(maxScroll) end
end

local function PanelLimits()
    local maxWidth = math.max(1, UIParent:GetWidth() - 20)
    local maxHeight = math.max(1, UIParent:GetHeight() - 20)
    return math.min(MIN_WIDTH, maxWidth), math.min(MIN_HEIGHT, maxHeight), maxWidth, maxHeight
end

local function FullRowWidth(name, reservedWidth, maxContentWidth)
    if name:GetTextScale() ~= 1 then name:SetTextScale(1) end
    local width = TextWidth(name)
    local available = math.max(1, maxContentWidth - reservedWidth - 2)
    if width > available then
        name:SetTextScale(available / width)
        width = available
    end
    return width + reservedWidth + 2
end

function ns.UpdateShoppingWindow()
    if not panel or not panel:IsShown() then return end
    local materials, entries = ns.GetShoppingMaterials(), ns.GetShoppingEntries()
    local empty = #entries == 0
    panel.clear:SetEnabled(not empty)
    panel.empty:SetShown(empty)
    panel.scroll:SetShown(not empty)
    panel.status:SetText(L[ns.GetShoppingExportStatus() or ""])

    local minWidth, minHeight, maxWidth, maxHeight = PanelLimits()
    local scrollPadding = SCROLL_LEFT + SCROLL_RIGHT
    local maxContentWidth = math.max(1, maxWidth - scrollPadding)
    local requiredContentWidth = 0
    local missingOnly = ns.db.shoppingMissingOnly
    local shownMaterials = 0
    local y = 26
    for _, material in ipairs(materials) do
        local hasEnough = material.owned and material.owned >= material.required
        if not missingOnly or material.isGold or not hasEnough then
            shownMaterials = shownMaterials + 1
            local row = GetMaterialRow(shownMaterials)
            local height = material.bindOnPickup and 35 or 22
            PositionRow(row, y, height)
            SetRowName(row, material.link or (material.isGold and L["Gold"] or material.name))
            row.binding:SetShown(material.bindOnPickup == true)
            row.amount:SetText(QuantityText(material.owned, material.isGold) .. " / " .. QuantityText(material.required, material.isGold))
            requiredContentWidth = math.max(requiredContentWidth, FullRowWidth(row.name, MATERIAL_RESERVED_WIDTH, maxContentWidth))
            if hasEnough then
                row.amount:SetTextColor(0.60, 0.87, 0.63)
            else
                row.amount:SetTextColor(0.96, 0.84, 0.67)
            end
            y = y + height
        end
    end
    for i = shownMaterials + 1, #materialRows do materialRows[i]:Hide() end

    panel.entriesHeader:ClearAllPoints()
    panel.entriesHeader:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 3, -y - 10)
    y = y + 32
    for i, entry in ipairs(entries) do
        local row = GetEntryRow(i)
        row.key = entry.key
        PositionRow(row, y, 26)
        SetRowName(row, entry.link or entry.name)
        row.amount:SetText("×" .. entry.quantity)
        local reservedWidth = ENTRY_RESERVED_WIDTH + TextWidth(row.amount)
        requiredContentWidth = math.max(requiredContentWidth, FullRowWidth(row.name, reservedWidth, maxContentWidth))
        y = y + 26
    end
    for i = #entries + 1, #entryRows do entryRows[i]:Hide() end
    panel.content:SetHeight(y + 4)
    minWidth = math.min(maxWidth, math.max(minWidth, requiredContentWidth + scrollPadding))
    panel:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    local currentWidth = panel:GetWidth()
    local width = math.max(minWidth, math.min(currentWidth, maxWidth))
    if width ~= currentWidth then panel:SetWidth(width) end
    ClampScroll()
end

local function ShoppingWindowPosition()
    local position = ns.char.shoppingWindowPosition
    if type(position) == "table" then return position end
end

local function SetPanelSize(position)
    local minWidth, minHeight, maxWidth, maxHeight = PanelLimits()
    local width = position and tonumber(position.width) or WIDTH
    local height = position and tonumber(position.height) or HEIGHT
    panel:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
    panel:SetSize(math.max(minWidth, math.min(width, maxWidth)), math.max(minHeight, math.min(height, maxHeight)))
end

local function HasDetachedPosition(position)
    return position and type(position.x) == "number" and type(position.y) == "number"
end

local function SetStandalonePoint(position)
    if HasDetachedPosition(position) then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", position.x, position.y)
    elseif panel.anchor == UIParent then
        panel:SetPoint("CENTER")
    else
        panel:SetPoint("TOPLEFT", panel.anchor, "TOPRIGHT", 8, 0)
    end
end

local function FinishInteraction()
    local interaction = panel.interaction
    if not interaction then return end
    panel.interaction = nil
    panel:StopMovingOrSizing()
    panel:SetUserPlaced(false)
    local position = ShoppingWindowPosition() or {}
    position.width, position.height = panel:GetWidth(), panel:GetHeight()
    if interaction == "move" or HasDetachedPosition(position) then
        local left, top = panel:GetLeft(), panel:GetTop()
        local originX, originY = UIParent:GetLeft(), UIParent:GetBottom()
        if left and top and originX and originY then
            position.x, position.y = left - originX, top - originY
        end
    end
    ns.char.shoppingWindowPosition = position
    panel:ClearAllPoints()
    SetStandalonePoint(position)
end

local function ShoppingAnchor(auction)
    return auction or mainWindow or UIParent
end

local function ApplyPanelLayout(anchor, auction)
    FinishInteraction()
    panel.anchor, panel.auction = anchor, auction
    panel:ClearAllPoints()
    if auction then
        SetPanelSize()
        local gap = AuctionTabOffset(auction) > 52 and auctionButton:GetWidth() or 0
        panel:SetPoint("TOPLEFT", auction, "TOPRIGHT", gap, -1)
        panel:SetPoint("BOTTOMLEFT", auction, "BOTTOMRIGHT", gap, 0)
    else
        local position = ShoppingWindowPosition()
        SetPanelSize(position)
        SetStandalonePoint(position)
    end
    panel.resize:SetShown(not auction)
end

local function CreatePanel()
    panel = CreateFrame("Frame", "ForeverBiSTooltipShoppingFrame", UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetResizable(true)
    SetPanelSize()
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:SetUserPlaced(false)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if self.auction or self.interaction then return end
        self.interaction = "move"
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", FinishInteraction)
    panel:SetScript("OnHide", function()
        FinishInteraction()
        UpdateAuctionTab()
    end)
    panel:SetScript("OnShow", function() ns.RefreshShoppingList() end)
    panel:SetBackdrop(frameBackdrop)
    panel:SetBackdropColor(0.105, 0.079, 0.060, 1)
    panel:SetBackdropBorderColor(0.78, 0.58, 0.37, 1)
    UISpecialFrames[#UISpecialFrames + 1] = "ForeverBiSTooltipShoppingFrame"

    local title = Text(panel, "GameFontNormal", 15)
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText(L["Shopping list"])
    title:SetTextColor(0.98, 0.81, 0.56)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", -7, -6)
    close:SetScript("OnClick", function() panel:Hide() end)

    panel.scroll = CreateFrame("ScrollFrame", "ForeverBiSTooltipShoppingScrollFrame", panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", SCROLL_LEFT, -52)
    panel.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_RIGHT, 55)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(math.max(1, panel:GetWidth() - SCROLL_LEFT - SCROLL_RIGHT), 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.scroll:HookScript("OnSizeChanged", function(_, width)
        panel.content:SetWidth(math.max(1, width))
        ClampScroll()
    end)

    local materialsHeader = Text(panel.content, "GameFontNormal", 13)
    materialsHeader:SetPoint("TOPLEFT", 3, -3)
    materialsHeader:SetText(L["Materials"])
    local amountsHeader = Text(panel.content, "GameFontNormal", 13)
    amountsHeader:SetPoint("TOPRIGHT", -3, -3)
    amountsHeader:SetText(L["Owned / Required"])
    local rule = panel.content:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 0, -21)
    rule:SetPoint("TOPRIGHT", 0, -21)
    rule:SetHeight(1)
    rule:SetColorTexture(0.69, 0.48, 0.28, 0.55)
    panel.entriesHeader = Text(panel.content, "GameFontNormal", 13)
    panel.entriesHeader:SetText(L["Tracked enhancements"])

    panel.empty = Text(panel, nil, 13)
    panel.empty:SetPoint("LEFT", 28, 0)
    panel.empty:SetPoint("RIGHT", -28, 0)
    panel.empty:SetJustifyH("CENTER")
    panel.empty:SetText(L["Click an enchant or gem in the BiS list to add its materials."])
    panel.clear = Button(panel, L["Clear list"], 122)
    panel.clear:SetPoint("BOTTOMRIGHT", -20, 19)
    panel.clear:SetScript("OnClick", ns.ClearShoppingList)
    panel.status = Text(panel, nil, 12)
    panel.status:SetPoint("BOTTOMLEFT", 20, 20)
    panel.status:SetPoint("BOTTOMRIGHT", -154, 20)
    panel.status:SetTextColor(0.80, 0.70, 0.57)

    panel.resize = CreateFrame("Button", nil, panel)
    panel.resize:SetSize(19, 19)
    panel.resize:SetPoint("BOTTOMRIGHT", -2, 2)
    panel.resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    panel.resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    panel.resize:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or panel.auction or panel.interaction then return end
        panel.interaction = "resize"
        panel:StartSizing("BOTTOMRIGHT")
    end)
    panel.resize:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and panel.interaction == "resize" then FinishInteraction() end
    end)
end

function ns.InitShoppingUI(window, text, button, backdrop, textWidth)
    mainWindow, Text, Button, frameBackdrop, TextWidth = window, text, button, backdrop, textWidth
end

local function ShowShoppingWindow(auction)
    if not panel then CreatePanel() end
    local anchor = ShoppingAnchor(auction)
    if auction or panel.anchor ~= anchor then ApplyPanelLayout(anchor, auction) end
    if panel:IsShown() then ns.UpdateShoppingWindow() else panel:Show() end
    UpdateAuctionTab()
end

function ns.ToggleShoppingWindow(auction)
    local anchor = ShoppingAnchor(auction)
    if panel and panel.anchor == anchor and panel:IsShown() then
        panel:Hide()
    else
        ShowShoppingWindow(auction)
    end
end

function ns.OpenShoppingWindow()
    if panel and panel:IsShown() then ns.RefreshShoppingList() else ShowShoppingWindow() end
end

function ns.CloseShoppingWindow()
    if panel then panel:Hide() end
end

function ns.ResetShoppingWindow()
    if panel then FinishInteraction() end
    ns.char.shoppingWindowPosition = nil
    if not panel then return end
    ApplyPanelLayout(mainWindow or UIParent)
    UpdateAuctionTab()
    if panel:IsShown() then ns.UpdateShoppingWindow() end
end

local function ShowAuctionButton()
    local auction = AuctionHouseFrame or AuctionFrame
    if AuctionFrame and AuctionFrame:IsShown() and (not auction or not auction:IsShown()) then
        auction = AuctionFrame
    end
    if not auction or not Button then return end
    if not auctionButton then
        auctionButton = CreateFrame("Frame", nil, auction, "LargeSideTabButtonTemplate")
        auctionButton.Icon:SetTexture("Interface\\Icons\\INV_Misc_Food_Vendor_GreenCabbage")
        auctionButton.Icon:SetSize(24, 24)
        auctionButton.tooltipText = L["Shopping list"]
        auctionButton:SetCustomOnMouseUpHandler(function(self, button, upInside)
            if button == "LeftButton" and upInside then ns.ToggleShoppingWindow(self:GetParent()) end
        end)
    end
    if auctionButton:GetParent() ~= auction then auctionButton:SetParent(auction) end
    if not hookedAuctions[auction] then
        hookedAuctions[auction] = true
        auction:HookScript("OnHide", function(self)
            if panel and panel.auction == self then panel:Hide() end
        end)
    end
    UpdateAuctionTab()
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
events:SetScript("OnEvent", function(_, event, interaction)
    local interactionTypes = Enum and Enum.PlayerInteractionType
    if event == "AUCTION_HOUSE_SHOW" or (interactionTypes and interaction == interactionTypes.Auctioneer) then
        if AuctionHouseFrame or AuctionFrame then
            ShowAuctionButton()
        else
            C_Timer.After(0, ShowAuctionButton)
        end
    end
end)
