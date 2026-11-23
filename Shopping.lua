local addonName, ns = ...

local L = ns.L
local listName = "Forever BiS Shopping"
local materials, requested = {}, {}
local exportStatus
local refreshPending
local legacyEnchants

local function PrintShoppingMessage(prefix, message)
    print("|cffa7d85e" .. prefix .. "|r: " .. message)
end

local function Public(value)
    if not issecretvalue or not issecretvalue(value) then return value end
end

local function PublicLink(value)
    value = Public(value)
    if type(value) == "string" and value ~= "" then return value end
end

local function RequestItemData(id)
    if not requested[id] and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        C_Item.RequestLoadItemDataByID(id)
    end
end

local function ShoppingMaterials(entry, isGem)
    if entry.requirements and #entry.requirements > 0 then return entry.requirements end
    if entry.reagents and #entry.reagents > 0 then return entry.reagents end
    if entry.itemID or entry.kind == "item" or isGem then
        return { { id = entry.itemID or entry.id, name = entry.name, count = 1 } }
    end
end

function ns.CanShopForEnhancement(entry, isGem)
    return entry.id ~= nil and ShoppingMaterials(entry, isGem) ~= nil
end

local function ShoppingEntries()
    return ns.char and ns.char.shoppingEntries
end

local function EnhancementKey(entry)
    return (entry.spellID and "spell" or entry.kind or "item") .. ":" .. entry.id
end

local function EnhancementTooltip(entry, isGem)
    local itemID = entry.itemID or (isGem and entry.id) or entry.recipeItemID
    if itemID then return "item", itemID end
    if entry.spellID or entry.kind == "spell" then return "spell", entry.spellID or entry.id end
    return "item", entry.id
end

local function LegacyTooltip(key)
    if not legacyEnchants then
        legacyEnchants = {}
        for _, list in pairs(ns.Lists) do
            for _, stage in pairs(list.stages) do
                for _, enchant in pairs(stage.enchants or {}) do
                    local enchantKey = EnhancementKey(enchant)
                    local previous = legacyEnchants[enchantKey]
                    if not previous or (enchant.itemID and not previous.itemID)
                        or (enchant.recipeItemID and not (previous.itemID or previous.recipeItemID)) then
                        legacyEnchants[enchantKey] = enchant
                    end
                end
            end
        end
    end
    local enchant = legacyEnchants[key]
    if enchant then return EnhancementTooltip(enchant) end
    local kind, id = key:match("^(%a+):(%d+)$")
    if kind == "item" or kind == "spell" then return kind, tonumber(id) end
end

local function EnhancementLink(kind, id)
    if not id then return end
    if kind == "spell" then
        if C_Spell and C_Spell.GetSpellLink then return PublicLink(C_Spell.GetSpellLink(id)) end
        return
    end
    local _, link = C_Item.GetItemInfo(id)
    link = PublicLink(link)
    if not link then RequestItemData(id) end
    return link
end

function ns.GetShoppingEntries()
    local result = {}
    for key, entry in pairs(ShoppingEntries() or {}) do
        local tooltipKind, tooltipID = entry.tooltipKind, entry.tooltipID
        if not tooltipID then tooltipKind, tooltipID = LegacyTooltip(key) end
        result[#result + 1] = {
            key = key, name = entry.name, quantity = entry.quantity, tooltipKind = tooltipKind, tooltipID = tooltipID,
            link = EnhancementLink(tooltipKind, tooltipID),
        }
    end
    table.sort(result, function(a, b)
        if a.name == b.name then return a.key < b.key end
        return a.name < b.name
    end)
    return result
end

function ns.GetShoppingMaterials()
    return materials
end

function ns.GetShoppingExportStatus()
    return exportStatus
end

local function ResolveMaterial(row)
    local id = row.id
    if not id then return end
    local name, link, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(id)
    name, bindType = Public(name), Public(bindType)
    row.link = PublicLink(link)
    if type(name) == "string" and name ~= "" then row.name, row.localizedName = name, name end
    local binding = Enum and Enum.ItemBind
    if type(bindType) == "number" and binding then
        row.bindOnPickup = row.bindOnPickup or
            (bindType ~= binding.None and bindType ~= binding.OnEquip and bindType ~= binding.OnUse)
        row.bindingKnown = true
    end
    if not row.link or not row.localizedName or not row.bindingKnown then RequestItemData(id) end
    row.owned = Public(C_Item.GetItemCount(id, true, false, true, true))
end

local function CollectMaterials(entries)
    local rows, byItem = {}, {}
    local gold = 0
    for _, entry in pairs(entries or {}) do
        gold = gold + (entry.gold or 0) * entry.quantity
        for _, material in ipairs(entry.materials) do
            local id = material.id
            if not id and material.name and C_Item.GetItemInfoInstant then
                id = Public(C_Item.GetItemInfoInstant(material.name))
            end
            local key = id or material.name
            local row = byItem[key]
            if not row then
                row = { id = id, name = material.name or ("#" .. id), required = 0 }
                rows[#rows + 1] = row
                byItem[key] = row
            end
            row.required = row.required + material.count * entry.quantity
            row.bindOnPickup = row.bindOnPickup or material.bindOnPickup
        end
    end
    for _, row in ipairs(rows) do ResolveMaterial(row) end
    table.sort(rows, function(a, b)
        if a.name == b.name then return (a.id or 0) < (b.id or 0) end
        return a.name < b.name
    end)
    if gold > 0 then
        local money = Public(GetMoney())
        rows[#rows + 1] = { name = L["Gold"], required = gold, owned = money and money / 10000, isGold = true }
    end
    return rows
end

local function AuctionatorAPI()
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetShoppingListItems and api.ConvertFromSearchString
        and api.ConvertToSearchString and api.CreateShoppingList then
        return api
    end
end

local function SearchStrings(api)
    local desired, terms, keys = {}, {}, {}
    local pending
    for _, row in ipairs(materials) do
        if not row.isGold and not row.bindOnPickup and (row.owned == nil or row.owned < row.required) then
            if row.owned ~= nil and row.localizedName and row.bindingKnown then
                local term = { searchString = row.localizedName, isExact = true, categoryKey = "" }
                local key = api.ConvertToSearchString(addonName, term)
                if not terms[key] then
                    terms[key] = term
                    term.quantity = 0
                    keys[#keys + 1] = key
                end
                terms[key].quantity = terms[key].quantity + row.required - row.owned
            else
                pending = true
            end
        end
    end
    local searches = {}
    for _, key in ipairs(keys) do
        local search = api.ConvertToSearchString(addonName, terms[key])
        desired[key] = search
        searches[#searches + 1] = search
    end
    return searches, desired, pending
end

local function UpdateAuctionator(api)
    local searches, desired, pending = SearchStrings(api)
    local status = pending and "Waiting for item names or inventory counts."

    local ok, existing = pcall(api.GetShoppingListItems, addonName, listName)
    if not ok then
        if type(existing) ~= "string" or not existing:find("List does not exist", 1, true) then
            return "Could not update the Auctionator list."
        end
        if #searches > 0 then api.CreateShoppingList(addonName, listName, searches) end
        return status
    end

    local matched, changes, retained = 0, {}, {}
    for _, old in ipairs(existing) do
        local term = api.ConvertFromSearchString(addonName, old)
        term.quantity = nil
        local key = api.ConvertToSearchString(addonName, term)
        local new = not retained[key] and desired[key] or nil
        if new then
            matched = matched + 1
            retained[key] = true
        end
        if new ~= old then changes[#changes + 1] = { old = old, new = new } end
    end
    if matched < #searches or (#changes > 0 and not (api.AlterShoppingListItem and api.DeleteShoppingListItem)) then
        api.CreateShoppingList(addonName, listName, searches)
    else
        for _, change in ipairs(changes) do
            if change.new then
                api.AlterShoppingListItem(addonName, listName, change.old, change.new)
            else
                api.DeleteShoppingListItem(addonName, listName, change.old)
            end
        end
    end
    return status
end

function ns.RefreshShoppingList()
    if not ns.char or InCombatLockdown() then return end
    local entries = ShoppingEntries()
    materials = CollectMaterials(entries)
    exportStatus = nil
    if entries or ns.db.shoppingListManaged then
        local api = AuctionatorAPI()
        if api then
            local ok, status = pcall(UpdateAuctionator, api)
            exportStatus = status
            if not ok then exportStatus = "Could not update the Auctionator list." end
        else
            exportStatus = "Auctionator is unavailable."
        end
    end
    if ns.UpdateShoppingWindow then ns.UpdateShoppingWindow() end
end

local function CanAddShoppingMaterials()
    if not InCombatLockdown() then return true end
    PrintShoppingMessage(listName, L["Add crafting materials after combat."])
    return false
end

function ns.ShopForEnhancement(entry, isGem)
    if not ns.char or not entry.id then return false end
    local inputs = ShoppingMaterials(entry, isGem)
    if not inputs then return false end
    if not CanAddShoppingMaterials() then return true end

    local name = entry.name or Public(C_Item.GetItemNameByID(entry.itemID or entry.id)) or ("#" .. entry.id)
    local key = EnhancementKey(entry)
    local entries = ShoppingEntries()
    if not entries then
        entries = {}
        ns.char.shoppingEntries = entries
    end
    ns.db.shoppingListManaged = true
    local previous = entries[key]
    local tooltipKind, tooltipID = EnhancementTooltip(entry, isGem)
    entries[key] = {
        name = name, quantity = (previous and previous.quantity or 0) + 1, gold = entry.requiredGold, materials = inputs,
        tooltipKind = tooltipKind, tooltipID = tooltipID,
    }
    if ns.db.shoppingAutoOpen ~= false and ns.OpenShoppingWindow then
        ns.OpenShoppingWindow()
    else
        ns.RefreshShoppingList()
    end
    PrintShoppingMessage(addonName, L["Added %s to the shopping list."]:format(name))
    return true
end

function ns.IncreaseShoppingEntry(key)
    local entries = ShoppingEntries()
    local entry = entries and entries[key]
    if not entry or not CanAddShoppingMaterials() then return end
    entry.quantity = entry.quantity + 1
    ns.RefreshShoppingList()
end

function ns.RemoveShoppingEntry(key)
    local entries = ShoppingEntries()
    local entry = entries and entries[key]
    if not entry then return end
    if entry.quantity > 1 then
        entry.quantity = entry.quantity - 1
    else
        entries[key] = nil
    end
    ns.RefreshShoppingList()
    return entry.name
end

function ns.RemoveShoppingEnhancement(entry)
    if not entry.id then return end
    local name = ns.RemoveShoppingEntry(EnhancementKey(entry))
    if name then
        PrintShoppingMessage(addonName, L["Removed one set for %s from the shopping list."]:format(name))
    end
end

function ns.ClearShoppingList()
    if not ShoppingEntries() then return end
    wipe(ns.char.shoppingEntries)
    ns.RefreshShoppingList()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, id)
    if not ns.db or not (ShoppingEntries() or ns.db.shoppingListManaged) or refreshPending then return end
    if event == "GET_ITEM_INFO_RECEIVED" and not requested[id] then return end
    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        ns.RefreshShoppingList()
    end)
end)
