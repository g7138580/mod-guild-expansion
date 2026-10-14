--[[
  Guild Expansion: Quartermaster page.
  Left: categories. Right: what the quartermaster sells in that category, for guild
  supplies. Rows unlock with guild level; consumables show the tier for the character's
  level. Services spend supplies on the guild's other systems (rerolls and the like).
]]

local GE = GuildExpansion
local UI = GE.UI

local LEFT_WIDTH = 180
local ROW_WIDTH = 344
local ROW_HEIGHT = 52
local ROWS_PER_COLUMN = 9
local PAGE_SIZE = ROWS_PER_COLUMN * 2

local CATEGORIES = {
    { id = 1, name = "Bags", icon = "INV_Misc_Bag_10" },
    { id = 2, name = "Profession Tools", icon = "Trade_Fishing" },
    { id = 3, name = "Consumables", icon = "INV_Potion_54" },
    { id = 4, name = "Services", icon = "INV_Crate_01" },
}

-- Keep in sync with QuartermasterService in src/GspeQuartermaster.h.
local SERVICES = {
    [1] = { name = "Reroll Recruits", icon = "INV_Scroll_03",
            desc = "Replace the guild's recruit candidates with new ones now." },
    [2] = { name = "Reroll Mission Board", icon = "INV_Misc_Map_01",
            desc = "Replace every mission offer on the board with new ones. Running missions are not affected." },
    [3] = { name = "Rush a Work Order", icon = "INV_Hammer_20",
            desc = "An abandoned work order's slot gets a new order now instead of after the wait." },
    [4] = { name = "Extra Contract Reroll", icon = "INV_Misc_Note_01",
            desc = "One more contract reroll for this character today." },
}

-- Keep in sync with QuartermasterRowState.
local STATE_TEXT = {
    [1] = "Guild level %d",
    [2] = "You can't use this",
    [3] = "Limit reached",
    [4] = "Nothing to do right now",
}

local selectedCategory = 1
local pageIndex = 1

local function RowName(row)
    if row.service > 0 then
        local s = SERVICES[row.service]
        return s and s.name or "Service", 1
    end
    local name, _, quality = GetItemInfo(row.item)
    return name, quality or 1
end

local function RowIcon(row)
    if row.service > 0 then
        local s = SERVICES[row.service]
        return "Interface\\Icons\\" .. (s and s.icon or "INV_Misc_QuestionMark")
    end
    return GE.ItemIcon(row.item)
end

local function RowsInCategory(category)
    local list = {}
    for _, row in ipairs(GE.qmStock) do
        if row.category == category then
            list[#list + 1] = row
        end
    end
    return list
end

StaticPopupDialogs["GUILDEXPANSION_QM_BUY"] = {
    text = "Buy %s for %s guild supplies?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, rowId)
        GE.Send("QBUY " .. rowId)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Buy(row)
    local name = RowName(row) or "this"
    if row.count > 1 then
        name = row.count .. "x " .. name
    end
    local dialog = StaticPopup_Show("GUILDEXPANSION_QM_BUY", name, row.cost)
    if dialog then
        dialog.data = row.id
    end
end

-- Categories ---------------------------------------------------------------------

local function BuildCategories(page)
    local ui = page.ui
    local left = UI.Inset(page.frame)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LEFT_WIDTH)

    local header = left:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -12)
    header:SetText("Quartermaster")

    ui.categoryButtons = {}
    for i, cat in ipairs(CATEGORIES) do
        local b = CreateFrame("Button", nil, left)
        b:SetWidth(LEFT_WIDTH - 20)
        b:SetHeight(36)
        b:SetPoint("TOPLEFT", 10, -40 - (i - 1) * 40)
        b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
        b:SetBackdropColor(0.15, 0.12, 0.08, 0.8)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.selected = b:CreateTexture(nil, "BORDER")
        b.selected:SetAllPoints(true)
        b.selected:SetTexture(0.3, 0.5, 0.9, 0.35)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetWidth(26)
        b.icon:SetHeight(26)
        b.icon:SetPoint("LEFT", 6, 0)
        b.icon:SetTexture("Interface\\Icons\\" .. cat.icon)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
        b.label:SetText(cat.name)
        b:SetScript("OnClick", function()
            selectedCategory = cat.id
            pageIndex = 1
            page.refresh(page)
        end)
        ui.categoryButtons[i] = b
    end

    ui.note = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.note:SetPoint("BOTTOMLEFT", 12, 12)
    ui.note:SetWidth(LEFT_WIDTH - 24)
    ui.note:SetJustifyH("LEFT")
    ui.note:SetText("Paid with guild supplies. Purchases go to your bags, or by mail if they are full.")
end

local function RefreshCategories(page)
    for i, b in ipairs(page.ui.categoryButtons) do
        if CATEGORIES[i].id == selectedCategory then
            b.selected:Show()
        else
            b.selected:Hide()
        end
    end
end

-- Rows ---------------------------------------------------------------------------

local function BuildRow(parent)
    local r = UI.ParchmentRow(parent, ROW_WIDTH, ROW_HEIGHT - 4)
    r:EnableMouse(false)

    r.icon = UI.IconButton(r, 36)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon.tooltip = function(self)
        local row = r.row
        if not row then
            return
        end
        if row.service > 0 then
            local s = SERVICES[row.service]
            GameTooltip:AddLine(s and s.name or "Service")
            if s then
                GameTooltip:AddLine(s.desc, 1, 1, 1, true)
            end
        else
            GameTooltip:SetHyperlink("item:" .. row.item)
        end
        if row.limit > 0 then
            GameTooltip:AddLine(string.format("Bought %d of %d", row.bought, row.limit), 0.8, 0.8, 0.8)
        end
    end
    r.icon:SetScript("OnClick", function()
        local row = r.row
        if row and row.item > 0 and IsModifiedClick("CHATLINK") then
            local _, link = GetItemInfo(row.item)
            if link then
                ChatEdit_InsertLink(link)
            end
        end
    end)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -1)
    r.name:SetWidth(200)
    r.name:SetJustifyH("LEFT")
    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetWidth(200)
    r.sub:SetJustifyH("LEFT")

    r.buy = UI.Button(r, "Buy", 60, 20)
    r.buy:SetPoint("BOTTOMRIGHT", -10, 8)
    r.buy:SetScript("OnClick", function()
        if r.row then
            Buy(r.row)
        end
    end)

    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.cost:SetPoint("TOPRIGHT", -12, -8)

    r:Hide()
    return r
end

local function BuildList(page)
    local ui = page.ui
    local right = UI.Inset(page.frame)
    right:SetPoint("TOPLEFT", LEFT_WIDTH + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)

    ui.listTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.listTitle:SetPoint("TOPLEFT", 14, -12)

    ui.rows = {}
    for i = 1, PAGE_SIZE do
        local r = BuildRow(right)
        local column = math.floor((i - 1) / ROWS_PER_COLUMN)
        local line = (i - 1) % ROWS_PER_COLUMN
        r:SetPoint("TOPLEFT", 10 + column * (ROW_WIDTH + 8), -40 - line * ROW_HEIGHT)
        ui.rows[i] = r
    end

    ui.empty = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.empty:SetPoint("TOPLEFT", 16, -46)

    ui.prev = UI.Button(right, "<", 30, 22)
    ui.prev:SetPoint("BOTTOMRIGHT", -80, 8)
    ui.prev:SetScript("OnClick", function()
        pageIndex = math.max(1, pageIndex - 1)
        page.refresh(page)
    end)
    ui.next = UI.Button(right, ">", 30, 22)
    ui.next:SetPoint("BOTTOMRIGHT", -10, 8)
    ui.next:SetScript("OnClick", function()
        pageIndex = pageIndex + 1
        page.refresh(page)
    end)
    ui.pageText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.pageText:SetPoint("RIGHT", ui.next, "LEFT", -6, 0)
end

local function RefreshList(page)
    local ui = page.ui
    local category = CATEGORIES[1]
    for _, c in ipairs(CATEGORIES) do
        if c.id == selectedCategory then
            category = c
        end
    end
    ui.listTitle:SetText(category.name)

    local rows = RowsInCategory(selectedCategory)
    local pages = math.max(1, math.ceil(#rows / PAGE_SIZE))
    pageIndex = math.min(pageIndex, pages)
    local supplies = GE.state and GE.state.supplies or 0
    local missingNames = false

    for i, r in ipairs(ui.rows) do
        local row = rows[(pageIndex - 1) * PAGE_SIZE + i]
        r.row = row
        if row then
            local name, quality = RowName(row)
            if not name then
                missingNames = true
                name = "Loading..."
            end
            r.icon.icon:SetTexture(RowIcon(row))
            r.icon.count:SetText(row.count > 1 and row.count or "")
            UI.SetBorderQuality(r.icon, row.service == 0 and quality or nil)
            r.name:SetText("|cff" .. GE.QualityHex(quality) .. name .. "|r")

            local ok = row.state == 0
            r.icon.icon:SetDesaturated(not ok)
            if ok then
                r.sub:SetText(row.limit > 0 and string.format("|cffaaaaaaBought %d of %d|r", row.bought, row.limit) or "")
            else
                r.sub:SetText("|cffff4040" .. string.format(STATE_TEXT[row.state] or "", row.guildLevel) .. "|r")
            end

            local affordable = supplies >= row.cost
            r.cost:SetText((affordable and "|cffffd200" or "|cffff4040") .. row.cost
                .. "|r |TInterface\\Icons\\INV_Crate_01:14:14:0:0|t")
            if ok and affordable then
                r.buy:Enable()
            else
                r.buy:Disable()
            end
            r:Show()
        else
            r:Hide()
        end
    end
    page.missingNames = missingNames

    if pages > 1 then
        ui.prev:Show()
        ui.next:Show()
        ui.pageText:SetText(pageIndex .. " / " .. pages)
        if pageIndex > 1 then ui.prev:Enable() else ui.prev:Disable() end
        if pageIndex < pages then ui.next:Enable() else ui.next:Disable() end
    else
        ui.prev:Hide()
        ui.next:Hide()
        ui.pageText:SetText("")
    end

    local status = GE.qmInfo.status
    if status == 1 then
        ui.empty:SetText("Join a guild to trade with the quartermaster.")
    elseif status == 2 then
        ui.empty:SetText("The quartermaster is turned off on this server.")
    elseif #rows == 0 then
        ui.empty:SetText("Nothing for sale here at your level.")
    else
        ui.empty:SetText("")
    end
end

-- Page ---------------------------------------------------------------------------

local function Build(page)
    page.ui = {}
    BuildCategories(page)
    BuildList(page)

    page.frame:SetScript("OnShow", function()
        GE.Send("QM")
    end)

    -- Item names the client hadn't cached arrive a moment later.
    local elapsedSince = 0
    page.frame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince >= 1 and page.missingNames then
            elapsedSince = 0
            page.refresh(page)
        end
    end)
end

local function Refresh(page)
    RefreshCategories(page)
    RefreshList(page)
end

UI.RegisterPage("quartermaster", "Quartermaster", "Guild Quartermaster", Build, Refresh)
