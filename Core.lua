local addonName, ns = ...

ns.Classes = {
    { id = "DRUID", label = "Druid" },
    { id = "HUNTER", label = "Hunter" },
    { id = "MAGE", label = "Mage" },
    { id = "PALADIN", label = "Paladin" },
    { id = "PRIEST", label = "Priest" },
    { id = "ROGUE", label = "Rogue" },
    { id = "SHAMAN", label = "Shaman" },
    { id = "WARLOCK", label = "Warlock" },
    { id = "WARRIOR", label = "Warrior" },
}

ns.Slots = {
    { id = "head", label = "Head" }, { id = "neck", label = "Neck" },
    { id = "shoulder", label = "Shoulders" }, { id = "back", label = "Back" },
    { id = "chest", label = "Chest" }, { id = "wrist", label = "Wrists" },
    { id = "hands", label = "Hands" }, { id = "waist", label = "Waist" },
    { id = "legs", label = "Legs" }, { id = "feet", label = "Feet" },
    { id = "finger1", label = "Ring 1" }, { id = "finger2", label = "Ring 2" },
    { id = "trinket1", label = "Trinket 1" }, { id = "trinket2", label = "Trinket 2" },
    { id = "weapon", label = "Main hand" }, { id = "offhand", label = "Off hand" },
    { id = "ranged", label = "Ranged" },
}

local stages = { { id = "pre-raid", label = "Pre-Raid" } }
local specByID, slotByID = {}, {}
local requested, owned, indexes = {}, {}, {}
local qualityIDs = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4, legendary = 5 }

for _, spec in ipairs(ns.Specs) do specByID[spec.id] = spec end
for _, slot in ipairs(ns.Slots) do slotByID[slot.id] = slot end

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

function ns.GetSpec(id)
    return specByID[id]
end

function ns.GetStageLabel(id)
    for _, stage in ipairs(stages) do
        if stage.id == id then return ns.L[stage.label] end
    end
    return id
end

function ns.GetSlotLabel(id)
    return ns.L[slotByID[id] and slotByID[id].label or id]
end

function ns.GetStages(specID)
    local entry = ns.Lists[specID or ns.char.spec]
    local result = {}
    for _, stage in ipairs(stages) do
        if entry and entry.stages[stage.id] then
            result[#result + 1] = { id = stage.id, label = ns.L[stage.label] }
        end
    end
    return result
end

function ns.HasRealistic(specID)
    local entry = ns.Lists[specID or ns.char.spec]
    return entry ~= nil and entry.stages[ns.char.stage .. "-realistic"] ~= nil
end

function ns.GetList(specID, stageID, realistic)
    local entry = ns.Lists[specID or ns.char.spec]
    if not entry then return end
    local stage = stageID or ns.char.stage
    if realistic == nil then realistic = ns.char.realistic end
    if realistic and entry.stages[stage .. "-realistic"] then stage = stage .. "-realistic" end
    return entry.stages[stage]
end

local refreshQueued = false

local function Refresh()
    if refreshQueued then return end
    refreshQueued = true
    local function Update()
        refreshQueued = false
        if ns.UIRefresh then ns.UIRefresh() end
        if ns.RefreshTooltips then ns.RefreshTooltips() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, Update) else Update() end
end

ns.Refresh = Refresh

function ns.SelectSpec(id)
    if not specByID[id] then return end
    ns.char.spec = id
    local available = ns.GetStages(id)
    if not ns.GetList(id, ns.char.stage, false) and available[1] then ns.char.stage = available[1].id end
    if not ns.HasRealistic(id) then ns.char.realistic = false end
    Refresh()
end

function ns.SelectStage(id)
    if not ns.GetList(ns.char.spec, id, false) then return end
    ns.char.stage = id
    if not ns.HasRealistic() then ns.char.realistic = false end
    Refresh()
end

function ns.SetRealistic(enabled)
    ns.char.realistic = enabled == true and ns.HasRealistic()
    Refresh()
end

function ns.GetSourceURL()
    return ns.Source.url .. ns.char.spec .. "/"
end

function ns.OrderedEntries(entries)
    for index, entry in ipairs(entries) do
        if entry.preferred then
            if index == 1 then return entries end
            local ordered = { entry }
            for i, other in ipairs(entries) do
                if i ~= index then ordered[#ordered + 1] = other end
            end
            return ordered
        end
    end
    return entries
end

local function Index(stageID, realistic)
    local key = stageID .. (realistic and ":realistic" or ":normal")
    if indexes[key] then return indexes[key] end
    local index = {}
    for _, spec in ipairs(ns.Specs) do
        local list = ns.GetList(spec.id, stageID, realistic)
        if list then
            local matches = {}
            for _, slot in ipairs(ns.Slots) do
                local entries = list.slots[slot.id]
                for rank, entry in ipairs(entries and ns.OrderedEntries(entries) or {}) do
                    local match = matches[entry.id]
                    if match then
                        match.rank = math.min(match.rank, rank)
                    else
                        match = { spec = spec, rank = rank }
                        matches[entry.id] = match
                        index[entry.id] = index[entry.id] or {}
                        index[entry.id][#index[entry.id] + 1] = match
                    end
                end
            end
        end
    end
    indexes[key] = index
    return index
end

function ns.GetMatches(itemID)
    if Secret(itemID) or type(itemID) ~= "number" then return {} end
    local matches = Index(ns.char.stage, ns.char.realistic)[itemID] or {}
    if ns.db.allSpecs then return matches end
    local result = {}
    for _, match in ipairs(matches) do
        if match.spec.id == ns.char.spec then result[#result + 1] = match end
    end
    return result
end

function ns.GetItemDisplay(itemID)
    local data = ns.Items[itemID] or {}
    local name, link, quality, icon, _
    if C_Item and C_Item.GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    end
    if Secret(name) then name = nil end
    if Secret(link) then link = nil end
    if Secret(quality) then quality = nil end
    if Secret(icon) then icon = nil end
    if not name and not requested[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    quality = quality or qualityIDs[data.rarity] or 1
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or { r = 1, g = 1, b = 1 }
    return {
        name = name or data.name or ("#" .. itemID), link = link,
        icon = icon or ("Interface\\Icons\\" .. (data.icon or "INV_Misc_QuestionMark")),
        color = { r = color.r, g = color.g, b = color.b },
    }
end

function ns.GetItemState(itemID)
    return owned[itemID]
end

local function AddOwned(itemID, state)
    if not Secret(itemID) and type(itemID) == "number" then
        if state == "equipped" or not owned[itemID] then owned[itemID] = state end
    end
end

local function ScanOwned()
    owned = {}
    if C_Container then
        for bag = 0, NUM_BAG_SLOTS or 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                AddOwned(C_Container.GetContainerItemID(bag, slot), "bags")
            end
        end
    end
    for slot = 1, 19 do AddOwned(GetInventoryItemID("player", slot), "equipped") end
end

local function Initialize()
    if type(ForeverBiSTooltipDB) ~= "table" then ForeverBiSTooltipDB = {} end
    if type(ForeverBiSTooltipCharDB) ~= "table" then ForeverBiSTooltipCharDB = {} end
    ns.db, ns.char = ForeverBiSTooltipDB, ForeverBiSTooltipCharDB
    for key, value in pairs({ tooltip = true, allSpecs = false, ctrlOnly = false, minimap = true }) do
        if type(ns.db[key]) ~= "boolean" then ns.db[key] = value end
    end
    if not specByID[ns.char.spec] then
        local _, classID = UnitClass("player")
        for _, spec in ipairs(ns.Specs) do
            if spec.class == classID then ns.char.spec = spec.id; break end
        end
        ns.char.spec = ns.char.spec or ns.Specs[1].id
    end
    ns.char.stage = ns.char.stage or "pre-raid"
    if not ns.GetList(ns.char.spec, ns.char.stage, false) then ns.char.stage = "pre-raid" end
    ns.char.realistic = ns.char.realistic == true and ns.HasRealistic()
end

SLASH_FOREVERBISTOOLTIP1 = "/bistooltip"
SLASH_FOREVERBISTOOLTIP2 = "/fbt"
SlashCmdList.FOREVERBISTOOLTIP = function()
    if ns.db and ns.ToggleUI then ns.ToggleUI() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, value)
    if event == "ADDON_LOADED" then
        if value == addonName then Initialize() end
    elseif not ns.db then
        return
    elseif event == "PLAYER_LOGIN" then
        ScanOwned()
        ns.InitTooltip()
        ns.InitUI()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if not Secret(value) and requested[value] == true then
            requested[value] = "done"
            Refresh()
        end
    else
        ScanOwned()
        Refresh()
    end
end)
