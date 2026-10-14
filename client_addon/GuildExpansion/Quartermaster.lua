--[[
  Guild Expansion: Quartermaster page.
  Left: categories. Right: what the quartermaster sells in that category, for guild
  supplies. Rows unlock with guild level; consumables show the tier for the character's
  level. Services spend supplies on the guild's other systems (rerolls and the like).
  Across the top: this week's stock, which changes at the weekly reset. Gear is rolled
  for each character; the rest is shared by the guild and can be bought once.
]]

local GE = GuildExpansion
local UI = GE.UI

local LEFT_WIDTH = 180
local STRIP_HEIGHT = 142
local ROW_WIDTH = 344
local ROW_HEIGHT = 50
local ROWS_PER_COLUMN = 7
local WEEKLY_SLOTS = 6
local CARD_WIDTH = 144
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
    [5] = "Already known",
    [6] = "Sold",
    [7] = "Nothing this week",
}

-- Keep in sync with QuartermasterWeeklySlot.
local WEEKLY_LABELS = { "Gear", "Gear", "Material", "Recipe", "Recipe", "Pet or Mount" }

local selectedCategory = 1
local pageIndex = 1

local function RowName(row)
    if row.service > 0 then
        local s = SERVICES[row.service]
        return s and s.name or "Service", 1
    end
    local name, _, quality = GetItemInfo(row.item)
    if not name then
        GE.CacheItem(row.item)
    end
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
    OnAccept = function(self, data)
        if data.weekly then
            GE.Send("QBUYW " .. data.id)
        else
            GE.Send("QBUY " .. data.id)
        end
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
        dialog.data = { id = row.id }
    end
end

-- Weekly stock --------------------------------------------------------------------

-- Link with the offer's random suffix, so the tooltip shows the exact item for sale.
local function OfferLink(offer)
    return string.format("item:%d:0:0:0:0:0:%d:%d:%d", offer.item, offer.randomProperty, offer.suffixFactor, UnitLevel("player"))
end

local function BuyWeekly(offer)
    local name = GetItemInfo(offer.item) or "this"
    if offer.count > 1 then
        name = offer.count .. "x " .. name
    end
    local dialog = StaticPopup_Show("GUILDEXPANSION_QM_BUY", name, offer.cost)
    if dialog then
        dialog.data = { id = offer.slot, weekly = true }
    end
end

local function BuildWeekly(page)
    local ui = page.ui
    local strip = UI.Inset(page.frame)
    strip:SetPoint("TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", 0, 0)
    strip:SetHeight(STRIP_HEIGHT)

    local title = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("This Week")
    ui.weeklyReset = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.weeklyReset:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local note = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPRIGHT", -12, -14)
    note:SetText("Gear is picked for you. Everything else is shared by the guild: one of each.")

    ui.weekly = {}
    for i = 1, WEEKLY_SLOTS do
        local card = UI.ParchmentRow(strip, CARD_WIDTH, 100)
        card:EnableMouse(false)
        card:SetPoint("TOPLEFT", 10 + (i - 1) * (CARD_WIDTH + 4), -32)

        card.label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.label:SetPoint("TOPLEFT", 8, -7)
        card.label:SetText(WEEKLY_LABELS[i])

        card.icon = UI.IconButton(card, 34)
        card.icon:SetPoint("TOPLEFT", 8, -22)
        card.icon.tooltip = function()
            local offer = card.offer
            if not offer or offer.item == 0 then
                GameTooltip:AddLine("Nothing this week")
                return
            end
            GameTooltip:SetHyperlink(OfferLink(offer))
            if offer.state == 6 and offer.buyer ~= "" then
                GameTooltip:AddLine("Bought by " .. offer.buyer, 0.8, 0.8, 0.8)
            end
        end
        card.icon:SetScript("OnClick", function()
            local offer = card.offer
            if offer and offer.item > 0 and IsModifiedClick("CHATLINK") then
                local _, link = GetItemInfo(OfferLink(offer))
                if link then
                    ChatEdit_InsertLink(link)
                end
            end
        end)

        card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 6, 0)
        card.name:SetWidth(CARD_WIDTH - 58)
        card.name:SetHeight(36)
        card.name:SetJustifyH("LEFT")
        card.name:SetJustifyV("TOP")

        card.cost = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.cost:SetPoint("BOTTOMLEFT", 9, 11)
        card.state = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.state:SetPoint("BOTTOMRIGHT", -9, 11)

        card.buy = UI.Button(card, "Buy", 50, 18)
        card.buy:SetPoint("BOTTOMRIGHT", -6, 7)
        card.buy:SetScript("OnClick", function()
            if card.offer then
                BuyWeekly(card.offer)
            end
        end)
        ui.weekly[i] = card
    end
end

local function RefreshWeekly(page)
    local ui = page.ui
    local supplies = GE.state and GE.state.supplies or 0
    local missing = false
    ui.weeklyReset:SetText("New stock in |cffffffff" .. UI.FormatDuration(GE.qmInfo.weeklyResetsAt - GetTime()) .. "|r")

    for i, card in ipairs(ui.weekly) do
        local offer = GE.qmWeekly[i]
        card.offer = offer
        if offer and offer.item > 0 then
            local name, _, quality = GetItemInfo(offer.item)
            if not name then
                GE.CacheItem(offer.item)
                missing = true
            end
            card.icon.icon:SetTexture(GE.ItemIcon(offer.item))
            card.icon.count:SetText(offer.count > 1 and offer.count or "")
            UI.SetBorderQuality(card.icon, quality)
            card.name:SetText("|cff" .. GE.QualityHex(quality or 1) .. (name or "Loading...") .. "|r")
            card.icon.icon:SetDesaturated(offer.state ~= 0)

            local affordable = supplies >= offer.cost
            card.cost:SetText((affordable and "|cffffd200" or "|cffff4040") .. offer.cost
                .. "|r |TInterface\\Icons\\INV_Crate_01:12:12:0:0|t")
            if offer.state == 0 then
                card.state:SetText("")
                card.buy:Show()
                if affordable then card.buy:Enable() else card.buy:Disable() end
            else
                card.buy:Hide()
                card.state:SetText("|cffff4040" .. (STATE_TEXT[offer.state] or "") .. "|r")
            end
        else
            card.icon.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            card.icon.icon:SetDesaturated(true)
            card.icon.count:SetText("")
            UI.SetBorderQuality(card.icon, nil)
            card.name:SetText("|cff808080Nothing this week|r")
            card.cost:SetText("")
            card.state:SetText("")
            card.buy:Hide()
        end
    end
    return missing
end

-- Categories ---------------------------------------------------------------------

local function BuildCategories(page)
    local ui = page.ui
    local left = UI.Inset(page.frame)
    left:SetPoint("TOPLEFT", 0, -(STRIP_HEIGHT + 6))
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
    right:SetPoint("TOPLEFT", LEFT_WIDTH + 8, -(STRIP_HEIGHT + 6))
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
    BuildWeekly(page)
    BuildCategories(page)
    BuildList(page)

    page.frame:SetScript("OnShow", function()
        GE.Send("QM")
    end)

    -- Item names the client hadn't cached arrive a moment later.
    local elapsedSince = 0
    page.frame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince < 1 then
            return
        end
        elapsedSince = 0
        if GE.qmInfo.status == 0 and GE.qmInfo.weeklyResetsAt > 0 and GE.qmInfo.weeklyResetsAt <= GetTime() then
            GE.qmInfo.weeklyResetsAt = GetTime() + 30
            GE.Send("QM")
        end
        if page.missingNames then
            page.refresh(page)
        else
            page.ui.weeklyReset:SetText("New stock in |cffffffff" .. UI.FormatDuration(GE.qmInfo.weeklyResetsAt - GetTime()) .. "|r")
        end
    end)
end

local function Refresh(page)
    RefreshCategories(page)
    RefreshList(page)
    if RefreshWeekly(page) then
        page.missingNames = true
    end
end

UI.RegisterPage("quartermaster", "Quartermaster", "Guild Quartermaster", Build, Refresh)
