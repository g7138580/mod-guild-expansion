--[[
  Guild Expansion: Missions page (Legion mission-table style).
  List view:   "Available" / "In Progress" tabs, parchment mission rows, mission-slot panel.
  Mission page: unit list on the left; threats, unit slots (drag or click units in),
               success chance, rewards and Start on the right.
  Result view: what a collected mission brought back.
]]

local GE = GuildExpansion
local UI = GE.UI

local ROW_HEIGHT = 74
local MAX_ROWS = 10
local MAX_UNIT_ROWS = 12
local LEFT_WIDTH = 290

local TYPES = {
    [0] = { name = "Patrol",     icon = "INV_Misc_Map_01" },
    [1] = { name = "Gathering",  icon = "INV_Misc_Herb_01" },
    [2] = { name = "Supply Run", icon = "INV_Crate_02" },
    [3] = { name = "Bounty",     icon = "Ability_Hunter_SniperShot" },
    [4] = { name = "Delve",      icon = "INV_Misc_Key_13" },
    [5] = { name = "Training",   icon = "Ability_DualWield" },
    [7] = { name = "Raid",       icon = "INV_Misc_Head_Dragon_01" },
}

-- Mission effects. Keep in sync with MissionEffect in src/GspeMissions.h.
local EFFECTS = {
    [1] = { name = "Slowing", icon = "Spell_Nature_Slow",            desc = "This mission takes twice as long." },
    [2] = { name = "Lethal",  icon = "Spell_Shadow_DeathScream",     desc = "Troops sent on this mission will die." },
    [3] = { name = "Cursed",  icon = "Spell_Shadow_CurseOfTounges",  desc = "This mission can't give bonus loot." },
    [4] = { name = "Costly",  icon = "INV_Misc_Coin_17",             desc = "This mission costs twice the supplies." },
}

local listTab = "available"   -- "available" or "running"
local view = "list"           -- "list", "mission" or "result"
local selectedId
local slots = {}              -- slot index -> unit id
local consumable              -- { bag, slot, item } sent with the mission
local lastPickup              -- bag and slot of the last item picked up from the bags
local dragUnit
local thePage

local function TemplateOf(m)
    return GE.missionTemplates[m.template] or { name = "Mission", type = 0, slots = 1, roles = {}, desc = "" }
end

local function TypeOf(m)
    return TYPES[TemplateOf(m).type] or TYPES[0]
end

local function FindOffer(id)
    for _, m in ipairs(GE.offers) do
        if m.id == id then
            return m
        end
    end
end

local function FindUnit(id)
    for _, list in ipairs({ GE.units, GE.troops }) do
        for _, u in ipairs(list) do
            if u.id == id then
                return u
            end
        end
    end
end

local function ConsumableArg()
    return consumable and string.format(" C%d.%d", consumable.bag, consumable.slot) or ""
end

-- The running mission a unit is on, if any.
local function MissionOfUnit(unitId)
    for _, m in ipairs(GE.running) do
        for _, id in ipairs(m.units) do
            if id == unitId then
                return m
            end
        end
    end
end

local function AssignedList()
    local out = {}
    for i = 1, 3 do
        if slots[i] then
            out[#out + 1] = slots[i]
        end
    end
    return out
end

local function IsAssigned(unitId)
    for i = 1, 3 do
        if slots[i] == unitId then
            return true
        end
    end
    return false
end

local function SendPreview()
    if selectedId then
        local list = AssignedList()
        GE.Send("MPREVIEW " .. selectedId .. ConsumableArg() .. (#list > 0 and (" " .. table.concat(list, " ")) or ""))
    end
end

local function OpenMission(id)
    selectedId = id
    slots = {}
    consumable = nil
    GE.chance = nil
    view = "mission"
    SendPreview()
    thePage.refresh(thePage)
end

local function Assign(slotIndex, unitId)
    local m = FindOffer(selectedId)
    if not m or slotIndex > TemplateOf(m).slots then
        return
    end
    for i = 1, 3 do
        if slots[i] == unitId then
            slots[i] = nil
        end
    end
    slots[slotIndex] = unitId
    SendPreview()
    thePage.refresh(thePage)
end

local function AssignToFreeSlot(unitId)
    local m = FindOffer(selectedId)
    if not m then
        return
    end
    for i = 1, TemplateOf(m).slots do
        if not slots[i] then
            Assign(i, unitId)
            return
        end
    end
    UIErrorsFrame:AddMessage("All slots are filled. Click a slot to remove a unit.", 1.0, 0.1, 0.1, 1.0)
end

local function DurationText(seconds)
    local text = UI.FormatDuration(seconds)
    return seconds >= 8 * 3600 and ("|cffff9933(" .. text .. ")|r") or ("|cffffffff(" .. text .. ")|r")
end

local function ThreatTooltip(self)
    local a = GE.ABILITIES[self.threat]
    if a then
        GameTooltip:AddLine(a.threat)
        GameTooltip:AddLine("Countered by: " .. a.name, 1, 1, 1)
    end
end

hooksecurefunc("PickupContainerItem", function(bag, slot)
    lastPickup = { bag = bag, slot = slot }
end)

-- List view ---------------------------------------------------------------

local function BuildList(page)
    local ui = page.ui
    local v = CreateFrame("Frame", nil, page.frame)
    v:SetAllPoints(true)
    ui.list = v

    ui.tabAvailable = UI.Button(v, "Available", 220, 28)
    ui.tabAvailable:SetPoint("TOPLEFT", 4, 0)
    ui.tabAvailable:SetScript("OnClick", function()
        listTab = "available"
        page.refresh(page)
    end)
    ui.tabRunning = UI.Button(v, "In Progress", 220, 28)
    ui.tabRunning:SetPoint("LEFT", ui.tabAvailable, "RIGHT", 6, 0)
    ui.tabRunning:SetScript("OnClick", function()
        listTab = "running"
        page.refresh(page)
    end)

    local inset = UI.Inset(v)
    inset:SetPoint("TOPLEFT", 0, -34)
    inset:SetPoint("BOTTOMRIGHT", 0, 96)

    ui.scroll = CreateFrame("ScrollFrame", "GuildExpansionMissionScroll", inset, "UIPanelScrollFrameTemplate")
    ui.scroll.scrollBarHideable = true
    ui.scroll:SetPoint("TOPLEFT", 8, -8)
    ui.scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.content:SetWidth(UI.CONTENT_WIDTH - 38)
    ui.content:SetHeight(1)
    ui.scroll:SetScrollChild(ui.content)

    local rowWidth = UI.CONTENT_WIDTH - 42
    ui.rows = {}
    for i = 1, MAX_ROWS do
        local row = UI.ParchmentRow(ui.content, rowWidth, ROW_HEIGHT - 6)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

        row.level = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        row.level:SetPoint("TOPLEFT", 16, -12)
        row.level:SetTextColor(1, 1, 1)
        row.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ilvl:SetPoint("TOP", row.level, "BOTTOM", 0, -2)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(42)
        row.icon:SetHeight(42)
        row.icon:SetPoint("LEFT", 76, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 14, 0)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -6)

        row.progress = CreateFrame("StatusBar", nil, row)
        row.progress:SetWidth(260)
        row.progress:SetHeight(6)
        row.progress:SetPoint("TOPLEFT", row.sub, "BOTTOMLEFT", 0, -5)
        row.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.progress:SetStatusBarColor(0.3, 0.6, 1)
        row.progress:SetMinMaxValues(0, 1)
        row.progress.bg = row.progress:CreateTexture(nil, "BACKGROUND")
        row.progress.bg:SetAllPoints(true)
        row.progress.bg:SetTexture(0, 0, 0, 0.6)

        row.threats = {}
        for t = 1, 4 do
            local tb = UI.IconButton(row, 24)
            tb.tooltip = ThreatTooltip
            if t == 1 then
                tb:SetPoint("LEFT", row, "LEFT", 470, 0)
            else
                tb:SetPoint("LEFT", row.threats[t - 1], "RIGHT", 4, 0)
            end
            row.threats[t] = tb
        end

        row.effect = UI.IconButton(row, 24)
        row.effect:SetPoint("LEFT", row.threats[4], "RIGHT", 14, 0)
        row.effect.border:SetVertexColor(1, 0.3, 0.3)
        row.effect.tooltip = function(self)
            local e = EFFECTS[self.effect]
            if e then
                GameTooltip:AddLine(e.name, 1, 0.3, 0.3)
                GameTooltip:AddLine(e.desc, 1, 1, 1, true)
            end
        end

        row.rewards = {}
        for r = 1, 5 do
            local rb = UI.IconButton(row, 38)
            if r == 1 then
                rb:SetPoint("RIGHT", row, "RIGHT", -14, 0)
            else
                rb:SetPoint("RIGHT", row.rewards[r - 1], "LEFT", -6, 0)
            end
            row.rewards[r] = rb
        end

        row.timer = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        row.timer:SetPoint("RIGHT", -20, 0)
        row.collect = UI.Button(row, "Collect", 110, 26)
        row.collect:SetPoint("RIGHT", -16, 0)

        row:SetScript("OnEnter", function(self)
            local m = self.mission
            if not m then
                return
            end
            local tmpl = TemplateOf(m)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine(tmpl.name)
            GameTooltip:AddLine(string.format("%d unit mission  -  level %d %s", tmpl.slots, m.level, TypeOf(m).name), 1, 1, 1)
            if tmpl.desc and tmpl.desc ~= "" then
                GameTooltip:AddLine(tmpl.desc, 0.8, 0.8, 0.8, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        ui.rows[i] = row
    end

    ui.empty = ui.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.empty:SetPoint("TOP", 0, -60)
    ui.empty:SetTextColor(0.6, 0.6, 0.6)

    -- Bottom panel, like Legion's Combat Ally box.
    local panel = UI.Inset(v)
    panel:SetPoint("BOTTOMLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", 0, 0)
    panel:SetHeight(88)
    panel:SetBackdropColor(0.18, 0.08, 0.04, 0.85)
    ui.panelIcon = panel:CreateTexture(nil, "ARTWORK")
    ui.panelIcon:SetWidth(56)
    ui.panelIcon:SetHeight(56)
    ui.panelIcon:SetPoint("LEFT", 20, 0)
    if SetPortraitToTexture then
        SetPortraitToTexture(ui.panelIcon, "Interface\\Icons\\INV_Misc_Map_01")
    else
        ui.panelIcon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    end
    ui.panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.panelTitle:SetPoint("TOPLEFT", ui.panelIcon, "TOPRIGHT", 16, -6)
    ui.panelText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.panelText:SetPoint("TOPLEFT", ui.panelTitle, "BOTTOMLEFT", 0, -6)
    ui.panelRefresh = UI.Button(panel, "Refresh", 90, 24)
    ui.panelRefresh:SetPoint("RIGHT", -18, 0)
    ui.panelRefresh:SetScript("OnClick", GE.RequestMissions)
end

local function RefreshList(page)
    local ui = page.ui
    local now = GetTime()

    ui.tabAvailable:SetText("Available - " .. #GE.offers)
    ui.tabRunning:SetText("In Progress - " .. #GE.running)
    if listTab == "available" then
        ui.tabAvailable:LockHighlight()
        ui.tabRunning:UnlockHighlight()
    else
        ui.tabRunning:LockHighlight()
        ui.tabAvailable:UnlockHighlight()
    end

    local list = listTab == "available" and GE.offers or GE.running
    for i, row in ipairs(ui.rows) do
        local m = list[i]
        row.mission = m
        if m then
            local tmpl = TemplateOf(m)
            row.level:SetText(m.level)
            row.ilvl:SetText("(" .. m.itemLevel .. ")")
            row.icon:SetTexture("Interface\\Icons\\" .. TypeOf(m).icon)
            row.name:SetText((m.rare and "|cff3399ffRare:|r " or "") .. tmpl.name .. "  " .. DurationText(m.duration))
            if m.rare then
                row.bg:SetVertexColor(0.25, 0.32, 0.5)
            else
                row.bg:SetVertexColor(0.42, 0.36, 0.28)
            end
            row.effect.effect = m.effect
            if EFFECTS[m.effect] then
                row.effect.icon:SetTexture("Interface\\Icons\\" .. EFFECTS[m.effect].icon)
                row.effect.border:Show()
                row.effect:Show()
            else
                row.effect:Hide()
            end

            for t, tb in ipairs(row.threats) do
                tb.threat = m.threats[t]
                if tb.threat and GE.ABILITIES[tb.threat] then
                    tb.icon:SetTexture("Interface\\Icons\\" .. GE.ABILITIES[tb.threat].icon)
                    tb:Show()
                else
                    tb:Hide()
                end
            end

            if listTab == "available" then
                local needs = {}
                for _, role in ipairs(tmpl.roles or {}) do
                    needs[#needs + 1] = GE.ROLES[role].name
                end
                row.sub:SetText(string.format("%d unit%s   |cffffd200Cost: %d supplies|r%s", tmpl.slots,
                    tmpl.slots == 1 and "" or "s", m.cost, #needs > 0 and ("   Needs " .. table.concat(needs, ", ")) or ""))
                row.progress:Hide()
                row.timer:Hide()
                row.collect:Hide()
                UI.FillRewards(row.rewards, m)
                row:SetScript("OnClick", function() OpenMission(m.id) end)
            else
                local names = {}
                for _, id in ipairs(m.units) do
                    local u = FindUnit(id)
                    names[#names + 1] = u and u.name or "?"
                end
                row.sub:SetText(table.concat(names, ", ") .. "   |cff80ff80" .. math.min(m.chance, 100) .. "% success|r")
                for _, rb in ipairs(row.rewards) do
                    rb:Hide()
                end
                local remaining = m.endsAt - now
                row.progress:SetValue(1 - math.max(0, remaining) / math.max(1, m.duration))
                row.progress:Show()
                if remaining > 0 then
                    row.timer:SetText(UI.FormatDuration(remaining))
                    row.timer:Show()
                    row.collect:Hide()
                else
                    row.timer:Hide()
                    row.collect:Show()
                    row.collect:SetScript("OnClick", function() GE.Send("MCOLLECT " .. m.id) end)
                end
                row:SetScript("OnClick", nil)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    ui.content:SetHeight(math.max(1, #list * ROW_HEIGHT))

    local info = GE.missionInfo
    if info.status == 1 then
        ui.empty:SetText("Join a guild to run missions.")
    elseif info.status == 2 then
        ui.empty:SetText("Missions are turned off on this server.")
    elseif #list == 0 then
        ui.empty:SetText(listTab == "available" and "No missions available right now." or "No missions in progress.")
    else
        ui.empty:SetText("")
    end

    local ready, done = 0, 0
    for _, u in ipairs(GE.units) do
        if u.status == 0 then
            ready = ready + 1
        end
    end
    for _, m in ipairs(GE.running) do
        if m.endsAt <= now then
            done = done + 1
        end
    end
    ui.panelTitle:SetText(string.format("Mission Slots: %d / %d", #GE.running, info.slots))
    local nextSlot = ({ [1] = 5, [2] = 12, [3] = 17, [4] = 22 })[info.slots]
    local text = string.format("%d unit%s ready.", ready, ready == 1 and "" or "s")
    if done > 0 then
        text = text .. string.format("  |cff80ff80%d mission%s ready to collect.|r", done, done == 1 and "" or "s")
    end
    if nextSlot then
        text = text .. string.format("  Another mission slot unlocks at guild level %d.", nextSlot)
    end
    ui.panelText:SetText(text)
end

-- Mission page ------------------------------------------------------------

local function UnitStatusText(u)
    if u.status == 1 then
        local m = MissionOfUnit(u.id)
        local remaining = m and (m.endsAt - GetTime()) or 0
        return remaining > 0 and ("|cffffd200On Mission - " .. UI.FormatDuration(remaining) .. "|r") or "|cff80ff80Mission complete|r"
    end
    return string.format("Level %d  -  iLvl %d", u.level, u.itemLevel)
end

local function BuildUnitList(page, parent)
    local ui = page.ui
    local left = UI.Inset(parent)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LEFT_WIDTH)

    local header = left:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -12)
    header:SetText("Units")
    ui.unitHint = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.unitHint:SetPoint("BOTTOMLEFT", 12, 10)
    ui.unitHint:SetPoint("BOTTOMRIGHT", -12, 10)
    ui.unitHint:SetJustifyH("LEFT")
    ui.unitHint:SetText("Drag a unit onto a slot, or click it to fill the next free slot.")

    ui.unitScroll = CreateFrame("ScrollFrame", "GuildExpansionMissionUnitScroll", left, "UIPanelScrollFrameTemplate")
    ui.unitScroll.scrollBarHideable = true
    ui.unitScroll:SetPoint("TOPLEFT", 8, -36)
    ui.unitScroll:SetPoint("BOTTOMRIGHT", -28, 40)
    ui.unitContent = CreateFrame("Frame", nil, ui.unitScroll)
    ui.unitContent:SetWidth(LEFT_WIDTH - 36)
    ui.unitContent:SetHeight(1)
    ui.unitScroll:SetScrollChild(ui.unitContent)

    ui.unitRows = {}
    for i = 1, MAX_UNIT_ROWS do
        local r = CreateFrame("Button", nil, ui.unitContent)
        r:SetWidth(LEFT_WIDTH - 40)
        r:SetHeight(56)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 60)
        r:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
        r:SetBackdropColor(0.15, 0.12, 0.08, 0.8)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r:RegisterForDrag("LeftButton")

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetWidth(42)
        r.icon:SetHeight(42)
        r.icon:SetPoint("LEFT", 6, 0)
        r.border = r:CreateTexture(nil, "OVERLAY")
        r.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        r.border:SetBlendMode("ADD")
        r.border:SetWidth(76)
        r.border:SetHeight(76)
        r.border:SetPoint("CENTER", r.icon, "CENTER")
        r.role = r:CreateTexture(nil, "OVERLAY")
        r.role:SetWidth(16)
        r.role:SetHeight(16)
        r.role:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 4, -4)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -2)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
        r.abilities = {}
        for a = 1, 2 do
            local ab = r:CreateTexture(nil, "ARTWORK")
            ab:SetWidth(18)
            ab:SetHeight(18)
            if a == 1 then
                ab:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -6, 6)
            else
                ab:SetPoint("RIGHT", r.abilities[1], "LEFT", -3, 0)
            end
            r.abilities[a] = ab
        end

        r:SetScript("OnClick", function(self)
            if self.available then
                AssignToFreeSlot(self.unitId)
            end
        end)
        r:SetScript("OnDragStart", function(self)
            if self.available then
                dragUnit = self.unitId
                SetCursor(self.iconPath)
            end
        end)
        r:SetScript("OnDragStop", function()
            ResetCursor()
            local id = dragUnit
            dragUnit = nil
            if not id then
                return
            end
            for s, slot in ipairs(ui.slots) do
                if slot:IsShown() and MouseIsOver(slot) then
                    Assign(s, id)
                    return
                end
            end
        end)
        r:SetScript("OnEnter", function(self)
            local u = self.unitId and FindUnit(self.unitId)
            if not u then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cff" .. GE.QualityHex(u.quality) .. u.name .. "|r")
            GameTooltip:AddLine(string.format("Level %d %s", u.level, GE.UnitDescription(u)), 1, 1, 1)
            for _, id in ipairs(u.abilities) do
                local a = GE.ABILITIES[id]
                if a then
                    GameTooltip:AddLine("|cff80c0ff" .. a.name .. "|r - counters " .. a.threat, 1, 1, 1)
                end
            end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        ui.unitRows[i] = r
    end
end

local function RefreshUnitList(page, mission)
    local ui = page.ui
    local threatSet = {}
    for _, t in ipairs(mission and mission.threats or {}) do
        threatSet[t] = true
    end

    local all = {}
    for _, u in ipairs(GE.units) do
        all[#all + 1] = u
    end
    for _, u in ipairs(GE.troops) do
        all[#all + 1] = u
    end
    ui.unitContent:SetHeight(math.max(1, #all * 60))

    for i, r in ipairs(ui.unitRows) do
        local u = all[i]
        if u then
            local ut = GE.unitTemplates[u.template]
            r.unitId = u.id
            r.available = u.status == 0 and not IsAssigned(u.id)
            r.iconPath = "Interface\\Icons\\" .. (ut and ut.icon or "INV_Misc_QuestionMark")
            r.icon:SetTexture(r.iconPath)
            r.icon:SetDesaturated(not r.available)
            r.border:SetVertexColor(GE.QualityRGB(u.quality))
            if ut then
                GE.SetRoleIcon(r.role, ut.role)
            else
                r.role:Hide()
            end
            r.name:SetText("|cff" .. GE.QualityHex(u.quality) .. u.name .. "|r")
            local status = UnitStatusText(u)
            if GE.IsTroop(u) and u.status == 0 then
                status = string.format("Troop  -  %d mission%s left", u.vitality, u.vitality == 1 and "" or "s")
            end
            r.info:SetText(IsAssigned(u.id) and "|cff80c0ffAssigned to this mission|r" or status)
            for a, tex in ipairs(r.abilities) do
                local def = GE.ABILITIES[u.abilities[a] or 0]
                if def then
                    tex:SetTexture("Interface\\Icons\\" .. def.icon)
                    tex:SetDesaturated(mission ~= nil and not threatSet[u.abilities[a]])
                    tex:Show()
                else
                    tex:Hide()
                end
            end
            r:SetAlpha(r.available and 1 or 0.55)
            r:Show()
        else
            r.unitId = nil
            r:Hide()
        end
    end
end

local function BuildMission(page)
    local ui = page.ui
    local v = CreateFrame("Frame", nil, page.frame)
    v:SetAllPoints(true)
    v:Hide()
    ui.mission = v

    BuildUnitList(page, v)

    local right = UI.Inset(v)
    right:SetPoint("TOPLEFT", LEFT_WIDTH + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.right = right

    ui.back = UI.Button(right, "< Back", 80, 22)
    ui.back:SetPoint("TOPLEFT", 12, -12)
    ui.back:SetScript("OnClick", function()
        view = "list"
        selectedId = nil
        page.refresh(page)
    end)

    ui.mTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.mTitle:SetPoint("TOPLEFT", 14, -42)
    ui.mInfo = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.mInfo:SetPoint("TOPLEFT", ui.mTitle, "BOTTOMLEFT", 0, -6)

    ui.mChance = right:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.mChance:SetPoint("TOPRIGHT", -20, -20)
    ui.mChanceLabel = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ui.mChanceLabel:SetPoint("TOPRIGHT", ui.mChance, "BOTTOMRIGHT", 0, -2)
    ui.mChanceLabel:SetText("Success Chance")
    ui.mBonus = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.mBonus:SetPoint("TOPRIGHT", ui.mChanceLabel, "BOTTOMRIGHT", 0, -4)

    ui.mDesc = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.mDesc:SetPoint("TOPLEFT", ui.mInfo, "BOTTOMLEFT", 0, -14)
    ui.mDesc:SetPoint("RIGHT", right, "RIGHT", -16, 0)
    ui.mDesc:SetJustifyH("LEFT")
    ui.mDesc:SetHeight(40)

    local threatsHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    threatsHeader:SetPoint("TOPLEFT", ui.mDesc, "BOTTOMLEFT", 0, -12)
    threatsHeader:SetText("Threats")

    ui.mThreats = {}
    for i = 1, 4 do
        local card = CreateFrame("Frame", nil, right)
        card:SetWidth(130)
        card:SetHeight(86)
        card:SetPoint("TOPLEFT", threatsHeader, "BOTTOMLEFT", (i - 1) * 140, -8)
        card.icon = UI.IconButton(card, 48)
        card.icon:SetPoint("TOP", 0, 0)
        card.icon.tooltip = ThreatTooltip
        card.check = card.icon:CreateTexture(nil, "OVERLAY")
        card.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        card.check:SetWidth(22)
        card.check:SetHeight(22)
        card.check:SetPoint("BOTTOMRIGHT", 6, -6)
        card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.name:SetPoint("TOP", card.icon, "BOTTOM", 0, -4)
        card.counter = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.counter:SetPoint("TOP", card.name, "BOTTOM", 0, -2)
        ui.mThreats[i] = card
    end

    ui.mNeeds = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.mNeeds:SetPoint("TOPLEFT", threatsHeader, "BOTTOMLEFT", 0, -104)

    local slotsHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    slotsHeader:SetPoint("TOPLEFT", ui.mNeeds, "BOTTOMLEFT", 0, -12)
    slotsHeader:SetText("Units Sent")

    ui.slots = {}
    for i = 1, 3 do
        local s = CreateFrame("Button", nil, right)
        s:SetWidth(72)
        s:SetHeight(72)
        s:SetPoint("TOPLEFT", slotsHeader, "BOTTOMLEFT", 10 + (i - 1) * 190, -10)
        s.bg = s:CreateTexture(nil, "BACKGROUND")
        s.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        s.bg:SetWidth(118)
        s.bg:SetHeight(118)
        s.bg:SetPoint("CENTER")
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetAllPoints(true)
        s.border = s:CreateTexture(nil, "OVERLAY")
        s.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        s.border:SetBlendMode("ADD")
        s.border:SetWidth(130)
        s.border:SetHeight(130)
        s.border:SetPoint("CENTER")
        s.name = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        s.name:SetPoint("TOPLEFT", s, "TOPRIGHT", 10, -8)
        s.name:SetWidth(100)
        s.name:SetJustifyH("LEFT")
        s.info = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.info:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -4)
        s.info:SetWidth(100)
        s.info:SetJustifyH("LEFT")
        s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        s:SetScript("OnClick", function(self)
            if slots[self.index] then
                slots[self.index] = nil
                SendPreview()
                page.refresh(page)
            end
        end)
        s:SetScript("OnReceiveDrag", function(self)
            if dragUnit then
                Assign(self.index, dragUnit)
                dragUnit = nil
                ResetCursor()
            end
        end)
        s:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if slots[self.index] then
                GameTooltip:AddLine("Click to take this unit off the mission.")
            else
                GameTooltip:AddLine("Empty slot")
                GameTooltip:AddLine("Drag a unit here, or click a unit in the list.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        s.index = i
        ui.slots[i] = s
    end

    ui.mEffect = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.mEffect:SetPoint("TOPLEFT", ui.mNeeds, "TOPLEFT", 300, 0)

    local rewardsHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rewardsHeader:SetPoint("TOPLEFT", slotsHeader, "BOTTOMLEFT", 0, -104)
    rewardsHeader:SetText("Rewards")

    -- Consumable: drag a potion, elixir, flask, food or bandage here for bonus success.
    local consHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    consHeader:SetPoint("TOPLEFT", rewardsHeader, "TOPLEFT", 360, 0)
    consHeader:SetText("Consumable")
    ui.mCons = UI.IconButton(right, 40)
    ui.mCons:SetPoint("TOPLEFT", consHeader, "BOTTOMLEFT", 0, -8)
    ui.mCons:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ui.mCons.bg = ui.mCons:CreateTexture(nil, "BACKGROUND")
    ui.mCons.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    ui.mCons.bg:SetWidth(66)
    ui.mCons.bg:SetHeight(66)
    ui.mCons.bg:SetPoint("CENTER")
    ui.mCons:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    ui.mConsText = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.mConsText:SetPoint("LEFT", ui.mCons, "RIGHT", 10, 0)
    ui.mConsText:SetWidth(150)
    ui.mConsText:SetJustifyH("LEFT")
    local function PlaceConsumable()
        local kind, itemId = GetCursorInfo()
        if kind ~= "item" then
            return false
        end
        local link = lastPickup and GetContainerItemLink(lastPickup.bag, lastPickup.slot)
        if link and tonumber(link:match("item:(%d+)")) == itemId then
            consumable = { bag = lastPickup.bag, slot = lastPickup.slot, item = itemId }
            SendPreview()
        else
            UIErrorsFrame:AddMessage("Drag the consumable from your bags.", 1.0, 0.1, 0.1, 1.0)
        end
        ClearCursor()
        page.refresh(page)
        return true
    end
    ui.mCons:SetScript("OnReceiveDrag", PlaceConsumable)
    ui.mCons:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            consumable = nil
            SendPreview()
            page.refresh(page)
        else
            PlaceConsumable()
        end
    end)
    ui.mCons.tooltip = function()
        if consumable then
            GameTooltip:SetHyperlink("item:" .. consumable.item)
            GameTooltip:AddLine("Used up when the mission starts. Right-click to remove.", 0, 1, 0, true)
        else
            GameTooltip:AddLine("Consumable")
            GameTooltip:AddLine("Drag a consumable near the mission's level here. Each kind does something different:", 1, 1, 1, true)
            for i = 1, 9 do
                local c = GE.CONSUMABLES[i]
                GameTooltip:AddLine("|cffffd200" .. c.name .. ":|r " .. c.desc, 1, 1, 1, true)
            end
            GameTooltip:AddLine("It is used up when the mission starts.", 0.8, 0.8, 0.8, true)
        end
    end
    ui.mRewards = {}
    for i = 1, 6 do
        local rb = UI.IconButton(right, 40)
        if i == 1 then
            rb:SetPoint("TOPLEFT", rewardsHeader, "BOTTOMLEFT", 0, -8)
        else
            rb:SetPoint("LEFT", ui.mRewards[i - 1], "RIGHT", 8, 0)
        end
        ui.mRewards[i] = rb
    end

    ui.mStart = UI.Button(right, "Start Mission", 180, 30)
    ui.mStart:SetPoint("BOTTOMRIGHT", -16, 16)
    ui.mStart:SetScript("OnClick", function()
        local list = AssignedList()
        if selectedId and #list > 0 then
            GE.Send("MSTART " .. selectedId .. ConsumableArg() .. " " .. table.concat(list, " "))
        end
    end)
    ui.mCost = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.mCost:SetPoint("RIGHT", ui.mStart, "LEFT", -16, 0)
end

local function RefreshMission(page)
    local ui = page.ui
    local m = FindOffer(selectedId)
    if not m then
        view = "list"
        selectedId = nil
        return false
    end

    local tmpl = TemplateOf(m)
    local chance = GE.chance and GE.chance.id == m.id and GE.chance or nil
    RefreshUnitList(page, m)

    ui.mTitle:SetText(tmpl.name)
    local duration = chance and chance.duration or m.duration
    ui.mInfo:SetText(string.format("%sLevel %d %s  -  %s  -  Item level %d", m.rare and "|cff3399ffRare|r  -  " or "",
        m.level, TypeOf(m).name, UI.FormatDuration(duration), m.itemLevel)
        .. (duration < m.duration and "  |cff80ff80(Hardy)|r" or ""))
    local effect = EFFECTS[m.effect]
    ui.mEffect:SetText(effect and ("|cffff5050" .. effect.name .. ":|r " .. effect.desc) or "")

    if consumable then
        ui.mCons.icon:SetTexture(GE.ItemIcon(consumable.item))
        ui.mCons.icon:Show()
        local kind = chance and GE.CONSUMABLES[chance.consumableKind or 0]
        ui.mConsText:SetText(kind and ("|cff80ff80" .. kind.name .. ":|r " .. kind.desc)
            or "|cffff4040Not usable for this mission|r")
    else
        ui.mCons.icon:Hide()
        ui.mConsText:SetText("|cffaaaaaaOptional: drag a consumable here|r")
    end
    ui.mDesc:SetText(tmpl.desc or "")

    local value = chance and chance.value or 0
    local color = value >= 100 and "|cff80ff80" or (value >= 60 and "|cffffd200" or "|cffff4040")
    ui.mChance:SetText(color .. math.min(value, 100) .. "%|r")
    ui.mBonus:SetText(value > 100 and string.format("|cff80c0ff%d%% bonus loot|r", value - 100) or "")

    for i, card in ipairs(ui.mThreats) do
        local threat = m.threats[i]
        local a = threat and GE.ABILITIES[threat]
        if a then
            card.icon.threat = threat
            card.icon.icon:SetTexture("Interface\\Icons\\" .. a.icon)
            local countered = chance and chance.countered[threat]
            card.icon.icon:SetDesaturated(not countered)
            if countered then
                card.check:Show()
                card.icon.border:SetVertexColor(0.3, 1, 0.3)
            else
                card.check:Hide()
                card.icon.border:SetVertexColor(1, 0.25, 0.25)
            end
            card.icon.border:Show()
            card.name:SetText(a.threat)
            card.counter:SetText("Counter: " .. a.name)
            card:Show()
        else
            card:Hide()
        end
    end

    local needs = {}
    for _, role in ipairs(tmpl.roles or {}) do
        local missing = chance and chance.missing[role]
        needs[#needs + 1] = (missing and "|cffff4040" or "|cff80ff80") .. GE.ROLES[role].name .. "|r"
    end
    ui.mNeeds:SetText(#needs > 0 and ("Needs: " .. table.concat(needs, ", ")) or "|cffaaaaaaAny units can go on this mission.|r")

    for i, s in ipairs(ui.slots) do
        if i > tmpl.slots then
            s:Hide()
        else
            local u = slots[i] and FindUnit(slots[i])
            if u then
                local ut = GE.unitTemplates[u.template]
                s.icon:SetTexture("Interface\\Icons\\" .. (ut and ut.icon or "INV_Misc_QuestionMark"))
                s.icon:Show()
                s.border:SetVertexColor(GE.QualityRGB(u.quality))
                s.border:Show()
                s.name:SetText("|cff" .. GE.QualityHex(u.quality) .. u.name .. "|r")
                s.info:SetText(string.format("Level %d  -  iLvl %d", u.level, u.itemLevel))
            else
                s.icon:Hide()
                s.border:Hide()
                s.name:SetText("|cff808080Empty|r")
                s.info:SetText("")
            end
            s:Show()
        end
    end

    UI.FillRewards(ui.mRewards, m)

    local supplies = GE.state and GE.state.supplies or 0
    local slotsFree = #GE.running < GE.missionInfo.slots
    if not slotsFree then
        ui.mCost:SetText("|cffff4040All mission slots are in use.|r")
    else
        ui.mCost:SetText(string.format("Cost: %s%d supplies|r", supplies >= m.cost and "|cffffd200" or "|cffff4040", m.cost))
    end
    if #AssignedList() > 0 and supplies >= m.cost and slotsFree then
        ui.mStart:Enable()
    else
        ui.mStart:Disable()
    end
    return true
end

-- Result view ---------------------------------------------------------------

local function BuildResult(page)
    local ui = page.ui
    local v = UI.Inset(page.frame)
    v:SetPoint("TOPLEFT", 120, -40)
    v:SetPoint("BOTTOMRIGHT", -120, 60)
    v:SetBackdropColor(0.05, 0.04, 0.03, 0.95)
    v:SetFrameLevel(page.frame:GetFrameLevel() + 10)
    v:Hide()
    ui.result = v

    ui.rTitle = v:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.rTitle:SetPoint("TOP", 0, -40)
    ui.rName = v:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ui.rName:SetPoint("TOP", ui.rTitle, "BOTTOM", 0, -10)
    ui.rBonus = v:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.rBonus:SetPoint("TOP", ui.rName, "BOTTOM", 0, -10)

    ui.rRewards = {}
    for i = 1, 9 do
        local rb = UI.IconButton(v, 48)
        ui.rRewards[i] = rb
    end

    ui.rBody = v:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.rBody:SetPoint("TOP", ui.rBonus, "BOTTOM", 0, -100)
    ui.rBody:SetWidth(520)
    ui.rBody:SetSpacing(6)

    ui.rOk = UI.Button(v, "OK", 140, 30)
    ui.rOk:SetPoint("BOTTOM", 0, 30)
    ui.rOk:SetScript("OnClick", function()
        view = "list"
        page.refresh(page)
    end)
end

local function RefreshResult(page)
    local ui = page.ui
    local res = GE.lastResult
    if not res then
        view = "list"
        return false
    end

    local tmpl = GE.missionTemplates[res.template]
    ui.rTitle:SetText(res.success and "|cff80ff80Mission Successful!|r" or "|cffff4040Mission Failed|r")
    ui.rName:SetText(tmpl and tmpl.name or "")
    ui.rBonus:SetText(res.bonus and "|cff80c0ffBonus rewards!|r" or "")

    local shown = UI.FillRewards(ui.rRewards, {
        gold = res.gold, guildXp = res.guildXp, supplies = res.supplies,
        item = res.item, itemCount = res.itemCount,
    })
    -- Actual items: gear, trait bonus materials, Treasure Hunter finds and salvage.
    for _, entry in ipairs({ { res.gear, 1 }, { res.extraItem, res.extraCount }, { res.treasure, 1 },
                             { res.salvageItem, res.salvageCount } }) do
        local itemId, count = entry[1], entry[2]
        if itemId > 0 and count > 0 and shown < #ui.rRewards then
            shown = shown + 1
            local rb = ui.rRewards[shown]
            local _, _, quality = GetItemInfo(itemId)
            rb.icon:SetTexture(GE.ItemIcon(itemId))
            rb.count:SetText(count > 1 and count or "")
            UI.SetBorderQuality(rb, quality or 1)
            rb.tooltip = function() GameTooltip:SetHyperlink("item:" .. itemId) end
            rb:Show()
        end
    end
    local width = shown * 56 - 8
    for i, rb in ipairs(ui.rRewards) do
        rb:ClearAllPoints()
        rb:SetPoint("TOPLEFT", ui.result, "TOP", -width / 2 + (i - 1) * 56, -150)
    end

    local lines = {}
    if not res.success then
        lines[#lines + 1] = "Half of the supply cost was returned."
    end
    if res.extraCount > 0 then
        lines[#lines + 1] = "|cffffd200Your units' gathering traits brought back extra materials.|r"
    end
    if res.treasure > 0 then
        lines[#lines + 1] = "|cffffd200A Treasure Hunter found an extra piece of gear.|r"
    end
    if res.salvageItem > 0 or res.salvageGold > 0 then
        lines[#lines + 1] = "|cff80c0ffSalvage found!|r" .. (res.salvageGold > 0 and ("  " .. GE.FormatMoney(res.salvageGold)) or "")
    end
    if res.troopsLost > 0 then
        lines[#lines + 1] = string.format("|cffff4040%d troop%s lost.|r", res.troopsLost, res.troopsLost == 1 and "" or "s")
    end
    if res.promotions > 0 then
        lines[#lines + 1] = string.format("|cffa335ee%d unit%s promoted!|r", res.promotions, res.promotions == 1 and " was" or "s were")
    end
    lines[#lines + 1] = "|cffcc88ffEach unit gained " .. GE.FormatNumber(res.unitXp) .. " XP|r"
        .. (res.levelUps > 0 and string.format("  |cff80ff80(%d level%s gained)|r", res.levelUps, res.levelUps == 1 and "" or "s") or "")
    ui.rBody:SetText(table.concat(lines, "\n"))
    return true
end

-- Page --------------------------------------------------------------------

local function Build(page)
    thePage = page
    page.ui = {}
    BuildList(page)
    BuildMission(page)
    BuildResult(page)

    page.frame:SetScript("OnShow", function()
        GE.RequestMissions()
        GE.RequestUnits()
    end)

    -- Keep timers ticking.
    local elapsedSince = 0
    page.frame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince >= 1 then
            elapsedSince = 0
            if view == "list" and listTab == "running" then
                RefreshList(page)
            elseif view == "mission" then
                RefreshUnitList(page, FindOffer(selectedId))
            end
        end
    end)
end

local function Refresh(page)
    local ui = page.ui
    ui.list:Hide()
    ui.mission:Hide()
    ui.result:Hide()

    if view == "mission" and RefreshMission(page) then
        ui.mission:Show()
        return
    end
    if view == "result" and RefreshResult(page) then
        ui.list:Show()
        RefreshList(page)
        ui.result:Show()
        return
    end
    view = "list"
    ui.list:Show()
    RefreshList(page)
end

GE.RegisterListener(function(event)
    if event == "result" then
        view = "result"
        listTab = "running"
    elseif event == "missions" and view == "mission" and not FindOffer(selectedId) then
        view = "list"           -- the mission was started (or left the board)
        listTab = "running"
        selectedId = nil
    end
    if thePage and UI.IsShowingPage("missions") then
        Refresh(thePage)
    end
end)

UI.RegisterPage("missions", "Missions", "Guild Missions", Build, Refresh)
