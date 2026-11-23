local _, ns = ...

local L = ns.L
local Text, Button, frameBackdrop
local panel, mainWindow, auctionButton
local materialRows, entryRows = {}, {}
local hookedAuctions = {}

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

local function GetMaterialRow(index)
    local row = materialRows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, panel.content)
    materialRows[index] = row
    row.amount = Text(row, nil, 13)
    row.amount:SetPoint("TOPRIGHT", -3, -3)
    row.amount:SetWidth(128)
    row.amount:SetJustifyH("RIGHT")
    row.name = Text(row, nil, 13)
    row.name:SetPoint("TOPLEFT", 3, -3)
    row.name:SetPoint("TOPRIGHT", row.amount, "TOPLEFT", -7, 0)
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
    row = CreateFrame("Frame", nil, panel.content)
    entryRows[index] = row
    row.remove = Button(row, "−", 22, 21)
    row.remove:SetPoint("RIGHT", -3, 0)
    row.remove:SetScript("OnClick", function() ns.RemoveShoppingEntry(row.key) end)
    row.amount = Text(row, nil, 13)
    row.amount:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
    row.name = Text(row, nil, 13)
    row.name:SetPoint("LEFT", 3, 0)
    row.name:SetPoint("RIGHT", row.amount, "LEFT", -7, 0)
    row.name:SetWordWrap(false)
    return row
end

local function QuantityText(quantity, isGold)
    if quantity == nil then return "—" end
    if isGold then quantity = math.floor(quantity) end
    return tostring(quantity)
end

function ns.UpdateShoppingWindow()
    if not panel or not panel:IsShown() then return end
    local materials, entries = ns.GetShoppingMaterials(), ns.GetShoppingEntries()
    local empty = #entries == 0
    panel.clear:SetEnabled(not empty)
    panel.empty:SetShown(empty)
    panel.scroll:SetShown(not empty)
    panel.status:SetText(L[ns.GetShoppingExportStatus() or ""])

    local y = 26
    for i, material in ipairs(materials) do
        local row = GetMaterialRow(i)
        local height = material.bindOnPickup and 35 or 22
        PositionRow(row, y, height)
        row.name:SetText(material.isGold and L["Gold"] or material.name)
        row.binding:SetShown(material.bindOnPickup == true)
        row.amount:SetText(QuantityText(material.owned, material.isGold) .. " / " .. QuantityText(material.required, material.isGold))
        if material.owned and material.owned >= material.required then
            row.amount:SetTextColor(0.60, 0.87, 0.63)
        else
            row.amount:SetTextColor(0.96, 0.84, 0.67)
        end
        y = y + height
    end
    for i = #materials + 1, #materialRows do materialRows[i]:Hide() end

    panel.entriesHeader:ClearAllPoints()
    panel.entriesHeader:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 3, -y - 10)
    y = y + 32
    for i, entry in ipairs(entries) do
        local row = GetEntryRow(i)
        PositionRow(row, y, 26)
        row.key = entry.key
        row.name:SetText(entry.name)
        row.amount:SetText("×" .. entry.quantity)
        y = y + 26
    end
    for i = #entries + 1, #entryRows do entryRows[i]:Hide() end
    panel.content:SetHeight(y + 4)
    local maxScroll = math.max(0, y + 4 - panel.scroll:GetHeight())
    if panel.scroll:GetVerticalScroll() > maxScroll then panel.scroll:SetVerticalScroll(maxScroll) end
end

local function CreatePanel()
    local width = math.min(490, UIParent:GetWidth() - 20)
    local height = math.min(470, UIParent:GetHeight() - 20)
    panel = CreateFrame("Frame", "ForeverBiSTooltipShoppingFrame", UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetSize(width, height)
    panel.undockedHeight = height
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not self.auction then self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
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
    panel.scroll:SetPoint("TOPLEFT", 20, -52)
    panel.scroll:SetPoint("BOTTOMRIGHT", -38, 55)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(width - 58, 1)
    panel.scroll:SetScrollChild(panel.content)

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
end

function ns.InitShoppingUI(window, text, button, backdrop)
    mainWindow, Text, Button, frameBackdrop = window, text, button, backdrop
end

function ns.ToggleShoppingWindow(auction)
    if not panel then CreatePanel() end
    local anchor = auction or mainWindow or UIParent
    if panel.anchor == anchor and panel:IsShown() then
        panel:Hide()
        return
    end
    if auction or panel.anchor ~= anchor then
        panel.anchor, panel.auction = anchor, auction
        panel:ClearAllPoints()
        if auction then
            local gap = AuctionTabOffset(auction) > 52 and auctionButton:GetWidth() or 0
            panel:SetPoint("TOPLEFT", auction, "TOPRIGHT", gap, -1)
            panel:SetPoint("BOTTOMLEFT", auction, "BOTTOMRIGHT", gap, 0)
        elseif anchor == UIParent then
            panel:SetHeight(panel.undockedHeight)
            panel:SetPoint("CENTER")
        else
            panel:SetHeight(panel.undockedHeight)
            panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
        end
    end
    if panel:IsShown() then ns.UpdateShoppingWindow() else panel:Show() end
    UpdateAuctionTab()
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
