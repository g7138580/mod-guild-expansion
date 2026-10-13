--[[
  Guild Expansion: Work Orders page (crafting-order style).
  Left: the character's open orders. Right: the selected order with its item slot,
  rewards and Turn In. Items go into the slot by dragging them from the bags or by
  Alt-clicking them in the bags while this page is open. The server checks every item
  and destroys exactly the placed items when the order is turned in.
]]

local GE = GuildExpansion
local UI = GE.UI

local LEFT_WIDTH = 300
local ROW_HEIGHT = 60
local MAX_ROWS = 6

local SKILL_NAMES = {
    [0] = "Anyone (cloth)",
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
    [755] = "Jewelcrafting", [773] = "Inscription",
}

local selectedId
local lastPickup        -- bag and slot of the last item picked up from the bags

local function ItemIdFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function SelectedOrder()
    return selectedId and GE.FindOrder(selectedId)
end

local function Place(order, bag, slot)
    GE.Send(string.format("PLACE %d %d %d", order.id, bag, slot))
end

-- Called when something is dropped on (or clicked onto) the order's slot.
local function PlaceFromCursor(order)
    local kind, itemId = GetCursorInfo()
    if kind ~= "item" then
        return false
    end

    local fromBags = lastPickup and ItemIdFromLink(GetContainerItemLink(lastPickup.bag, lastPickup.slot)) == itemId
    if not fromBags then
        UIErrorsFrame:AddMessage("Drag the item from your bags.", 1.0, 0.1, 0.1, 1.0)
    elseif itemId ~= order.item then
        UIErrorsFrame:AddMessage("That item isn't what this order needs.", 1.0, 0.1, 0.1, 1.0)
    else
        Place(order, lastPickup.bag, lastPickup.slot)
    end
    ClearCursor()
    return true
end

hooksecurefunc("PickupContainerItem", function(bag, slot)
    lastPickup = { bag = bag, slot = slot }
end)

-- Alt-click an item in the bags to put it into the first order that needs it.
if ContainerFrameItemButton_OnModifiedClick then
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
        if not IsAltKeyDown() or not UI.IsShowingPage("orders") then
            return
        end
        local bag, slot = self:GetParent():GetID(), self:GetID()
        local itemId = ItemIdFromLink(GetContainerItemLink(bag, slot))
        if not itemId then
            return
        end
        local selected = SelectedOrder()
        if selected and selected.item == itemId and selected.placed < selected.quantity then
            Place(selected, bag, slot)
            return
        end
        for _, order in ipairs(GE.orders) do
            if order.item == itemId and order.placed < order.quantity then
                Place(order, bag, slot)
                return
            end
        end
        UIErrorsFrame:AddMessage("No open work order needs that item.", 1.0, 0.1, 0.1, 1.0)
    end)
end

StaticPopupDialogs["GUILDEXPANSION_ABANDON_ORDER"] = {
    text = "Abandon this work order? A new one will replace it.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, orderId)
        GE.Send("ABANDON " .. orderId)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Left list -----------------------------------------------------------------

local function BuildList(page)
    local ui = page.ui
    local left = UI.Inset(page.frame)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LEFT_WIDTH)

    ui.count = left:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.count:SetPoint("TOPLEFT", 12, -12)

    ui.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, left)
        r:SetWidth(LEFT_WIDTH - 20)
        r:SetHeight(ROW_HEIGHT - 4)
        r:SetPoint("TOPLEFT", 10, -40 - (i - 1) * ROW_HEIGHT)
        r:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
        r:SetBackdropColor(0.15, 0.12, 0.08, 0.8)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.selected = r:CreateTexture(nil, "BORDER")
        r.selected:SetAllPoints(true)
        r.selected:SetTexture(0.3, 0.5, 0.9, 0.35)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetWidth(40)
        r.icon:SetHeight(40)
        r.icon:SetPoint("LEFT", 8, 0)
        r.border = r:CreateTexture(nil, "OVERLAY")
        r.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        r.border:SetBlendMode("ADD")
        r.border:SetWidth(72)
        r.border:SetHeight(72)
        r.border:SetPoint("CENTER", r.icon, "CENTER")
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -2)
        r.name:SetWidth(190)
        r.name:SetJustifyH("LEFT")
        r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
        r.progress = r:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        r.progress:SetPoint("BOTTOMRIGHT", -8, 6)

        r:SetScript("OnClick", function(self)
            selectedId = self.orderId
            page.refresh(page)
        end)
        r:Hide()
        ui.rows[i] = r
    end

    ui.listEmpty = left:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.listEmpty:SetPoint("TOPLEFT", 14, -46)
    ui.listEmpty:SetWidth(LEFT_WIDTH - 28)
    ui.listEmpty:SetJustifyH("LEFT")

    ui.refresh = UI.Button(left, "Refresh", 90, 22)
    ui.refresh:SetPoint("BOTTOMLEFT", 10, 10)
    ui.refresh:SetScript("OnClick", function() GE.RequestSync(true) end)
end

local function RefreshList(page)
    local ui = page.ui
    ui.count:SetText(string.format("Work Orders: |cffffffff%d|r", #GE.orders))

    for i, r in ipairs(ui.rows) do
        local o = GE.orders[i]
        if o then
            r.orderId = o.id
            r.icon:SetTexture(GE.ItemIcon(o.item))
            r.border:SetVertexColor(GE.QualityRGB(o.quality))
            r.name:SetText("|cff" .. GE.QualityHex(o.quality) .. o.name .. "|r")
            r.sub:SetText((o.kind == 0 and "Craft" or "Gather") .. " - " .. (SKILL_NAMES[o.skill] or "Profession"))
            local done = o.placed >= o.quantity
            r.progress:SetText((done and "|cff80ff80" or "|cffffffff") .. o.placed .. " / " .. o.quantity .. "|r")
            if o.id == selectedId then
                r.selected:Show()
            else
                r.selected:Hide()
            end
            r:Show()
        else
            r.orderId = nil
            r:Hide()
        end
    end

    if GE.ordersStatus == 1 then
        ui.listEmpty:SetText("Join a guild to receive work orders.")
    elseif GE.ordersStatus == 2 then
        ui.listEmpty:SetText("Work orders are turned off on this server.")
    elseif #GE.orders == 0 then
        ui.listEmpty:SetText("No work orders right now. Learn a profession, or gather cloth from humanoids.")
    else
        ui.listEmpty:SetText("")
    end
end

-- Right detail ----------------------------------------------------------------

local function BuildDetail(page)
    local ui = page.ui
    local right = UI.Inset(page.frame)
    right:SetPoint("TOPLEFT", LEFT_WIDTH + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.right = right

    local d = CreateFrame("Frame", nil, right)
    d:SetAllPoints(true)
    ui.detail = d

    ui.dIcon = UI.IconButton(d, 52)
    ui.dIcon:SetPoint("TOPLEFT", 20, -20)
    ui.dIcon.tooltip = function()
        local o = SelectedOrder()
        if o then
            GameTooltip:SetHyperlink("item:" .. o.item)
        end
    end
    ui.dName = d:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.dName:SetPoint("TOPLEFT", ui.dIcon, "TOPRIGHT", 14, -2)
    ui.dRequires = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.dRequires:SetPoint("TOPLEFT", ui.dName, "BOTTOMLEFT", 0, -6)
    ui.dExpires = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.dExpires:SetPoint("TOPRIGHT", -20, -22)

    -- Requested items: the slot the items go into.
    local reqHeader = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    reqHeader:SetPoint("TOPLEFT", ui.dIcon, "BOTTOMLEFT", 0, -30)
    reqHeader:SetText("Requested Items")

    ui.slot = UI.IconButton(d, 64)
    ui.slot:SetPoint("TOPLEFT", reqHeader, "BOTTOMLEFT", 6, -14)
    ui.slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ui.slot.bg = ui.slot:CreateTexture(nil, "BACKGROUND")
    ui.slot.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    ui.slot.bg:SetWidth(104)
    ui.slot.bg:SetHeight(104)
    ui.slot.bg:SetPoint("CENTER")
    ui.slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ui.slot.count:SetFontObject("NumberFontNormalLarge")
    ui.slot.tooltip = function()
        local o = SelectedOrder()
        if not o then
            return
        end
        GameTooltip:SetHyperlink("item:" .. o.item)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Drag this item here from your bags, or Alt-click it in your bags.", 0, 1, 0, true)
        GameTooltip:AddLine("Right-click to take the items back out.", 0, 1, 0, true)
    end
    ui.slot:SetScript("OnReceiveDrag", function()
        local o = SelectedOrder()
        if o then
            PlaceFromCursor(o)
        end
    end)
    ui.slot:SetScript("OnClick", function(self, button)
        local o = SelectedOrder()
        if not o then
            return
        end
        if button == "RightButton" then
            GE.Send("CLEAR " .. o.id)
        elseif not PlaceFromCursor(o) and IsModifiedClick("CHATLINK") then
            local _, link = GetItemInfo(o.item)
            if link then
                ChatEdit_InsertLink(link)
            end
        end
    end)

    ui.slotName = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ui.slotName:SetPoint("TOPLEFT", ui.slot, "TOPRIGHT", 18, -4)
    ui.slotProgress = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.slotProgress:SetPoint("TOPLEFT", ui.slotName, "BOTTOMLEFT", 0, -6)
    ui.slotHint = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.slotHint:SetPoint("TOPLEFT", ui.slotProgress, "BOTTOMLEFT", 0, -6)
    ui.slotHint:SetText("Drag or Alt-click items into the slot. Right-click it to take them back.")

    ui.fill = UI.Button(d, "Fill from Bags", 130, 24)
    ui.fill:SetPoint("TOPLEFT", ui.slot, "BOTTOMLEFT", -6, -24)
    ui.fill:SetScript("OnClick", function()
        local o = SelectedOrder()
        if o then
            GE.Send("FILL " .. o.id)
        end
    end)

    -- Rewards, like a crafting order's commission box.
    local box = UI.Inset(d)
    box:SetPoint("TOPLEFT", ui.fill, "BOTTOMLEFT", 0, -24)
    box:SetWidth(300)
    box:SetHeight(140)
    box:SetBackdropColor(0.12, 0.09, 0.05, 0.9)
    local boxTitle = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    boxTitle:SetPoint("TOP", 0, -12)
    boxTitle:SetText("Commission")
    ui.rewardLines = {}
    local labels = { "Payment", "Guild XP", "Guild Supplies" }
    for i, label in ipairs(labels) do
        local l = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", 16, -24 - i * 28)
        l:SetText(label .. ":")
        local v = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPRIGHT", -16, -24 - i * 28)
        ui.rewardLines[i] = v
    end

    ui.turnIn = UI.Button(d, "Turn In", 160, 30)
    ui.turnIn:SetPoint("BOTTOMRIGHT", -20, 20)
    ui.turnIn:SetScript("OnClick", function()
        local o = SelectedOrder()
        if o then
            GE.Send("TURNIN " .. o.id)
        end
    end)
    ui.abandon = UI.Button(d, "Abandon", 110, 24)
    ui.abandon:SetPoint("BOTTOMLEFT", 20, 22)
    ui.abandon:SetScript("OnClick", function()
        local o = SelectedOrder()
        if o then
            local dialog = StaticPopup_Show("GUILDEXPANSION_ABANDON_ORDER")
            if dialog then
                dialog.data = o.id
            end
        end
    end)

    ui.dEmpty = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.dEmpty:SetPoint("CENTER")
end

local function RefreshDetail(page)
    local ui = page.ui
    local o = SelectedOrder()
    if not o then
        ui.detail:Hide()
        ui.dEmpty:SetText(#GE.orders > 0 and "Select a work order." or "")
        return
    end
    ui.detail:Show()
    ui.dEmpty:SetText("")

    local icon = GE.ItemIcon(o.item)
    ui.dIcon.icon:SetTexture(icon)
    UI.SetBorderQuality(ui.dIcon, o.quality)
    ui.dName:SetText("|cff" .. GE.QualityHex(o.quality) .. o.name .. "|r")

    local requires
    if o.kind == 0 then
        requires = "Requires: |cffffffff" .. (SKILL_NAMES[o.skill] or "Profession") .. "|r"
        local recipe = o.spell > 0 and GetSpellInfo(o.spell)
        if recipe and recipe ~= o.name then
            requires = requires .. "  |cffaaaaaa(" .. recipe .. ")|r"
        end
    else
        requires = "Gather: |cffffffff" .. (SKILL_NAMES[o.skill] or "Profession") .. "|r"
    end
    ui.dRequires:SetText(requires)
    ui.dExpires:SetText("Expires in " .. UI.FormatDuration(o.expiresAt - GetTime()))

    local done = o.placed >= o.quantity
    local inBags = GetItemCount(o.item)
    ui.slot.icon:SetTexture(icon)
    ui.slot.icon:SetDesaturated(o.placed == 0)
    UI.SetBorderQuality(ui.slot, o.quality)
    ui.slot.count:SetText((done and "|cff80ff80" or "|cffffffff") .. o.placed .. "/" .. o.quantity .. "|r")
    ui.slotName:SetText(o.quantity .. "x " .. o.name)
    ui.slotProgress:SetText(string.format("Placed |cffffffff%d / %d|r      In bags: |cffffffff%d|r", o.placed, o.quantity, inBags))

    ui.rewardLines[1]:SetText(GE.FormatMoney(o.gold))
    ui.rewardLines[2]:SetText("|cff4da6ff" .. GE.FormatNumber(o.guildXp) .. "|r")
    ui.rewardLines[3]:SetText("|cffffd200" .. o.supplies .. "|r")

    if done then
        ui.turnIn:Enable()
    else
        ui.turnIn:Disable()
    end
    if not done and inBags > o.placed then
        ui.fill:Enable()
    else
        ui.fill:Disable()
    end
end

-- Page ------------------------------------------------------------------------

local function Build(page)
    page.ui = {}
    BuildList(page)
    BuildDetail(page)

    -- Keep "In bags" counts and expiry times current while the page is open.
    page.frame:RegisterEvent("BAG_UPDATE")
    page.frame:SetScript("OnEvent", function()
        if page.frame:IsShown() then
            page.refresh(page)
        end
    end)
    local elapsedSince = 0
    page.frame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince >= 30 then
            elapsedSince = 0
            page.refresh(page)
        end
    end)
end

local function Refresh(page)
    if not SelectedOrder() then
        selectedId = GE.orders[1] and GE.orders[1].id or nil
    end
    RefreshList(page)
    RefreshDetail(page)
end

UI.RegisterPage("orders", "Work Orders", "Guild Work Orders", Build, Refresh)
