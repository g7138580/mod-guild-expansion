--[[
  Guild Expansion: Units page (Legion followers style).
  Left: the roster, troops (and troop training), and recruit candidates. Right: details of
  the selected entry, with Dismiss, Train or Recruit.
]]

local GE = GuildExpansion
local UI = GE.UI

local LEFT_WIDTH = 300
local ROW_HEIGHT = 60
local MAX_ROWS = 24

local selectedId        -- unit id, or "train:<template>" for a troop type
local thePage
local lastPickup        -- bag and slot of the last item picked up from the bags

hooksecurefunc("PickupContainerItem", function(bag, slot)
    lastPickup = { bag = bag, slot = slot }
end)

StaticPopupDialogs["GUILDEXPANSION_GIVE_GEAR"] = {
    text = "Give %s to %s? The item is used up.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, data)
        GE.Send(string.format("EQUIP %d %s %d %d", data.unit, data.key, data.bag, data.slot))
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["GUILDEXPANSION_DISMISS_UNIT"] = {
    text = "Dismiss %s from the guild? This can't be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, unitId)
        GE.Send("DISMISS " .. unitId)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Troop types that can be trained, as list entries.
local function TrainEntries()
    local list = {}
    for id, tmpl in pairs(GE.unitTemplates) do
        if tmpl.kind == 2 then
            list[#list + 1] = { train = true, id = "train:" .. id, template = id, quality = 2, level = GE.unitInfo.cap,
                                itemLevel = 0, abilities = {}, traits = {}, name = tmpl.name }
        end
    end
    table.sort(list, function(a, b) return a.template < b.template end)
    return list
end

local function AllEntries()
    local list = {}
    for _, group in ipairs({ GE.units, GE.troops, TrainEntries(), GE.candidates }) do
        for _, u in ipairs(group) do
            list[#list + 1] = u
        end
    end
    return list
end

local function FindEntry(id)
    for _, u in ipairs(AllEntries()) do
        if u.id == id then
            return u
        end
    end
end

local function MissionOfUnit(unitId)
    for _, m in ipairs(GE.running) do
        for _, id in ipairs(m.units) do
            if id == unitId then
                return m
            end
        end
    end
end

local function IconPath(u)
    local ut = GE.unitTemplates[u.template]
    return "Interface\\Icons\\" .. (ut and ut.icon or "INV_Misc_QuestionMark")
end

local function MissionsLeft(u)
    return string.format("%d mission%s left", u.vitality, u.vitality == 1 and "" or "s")
end

-- Left list ------------------------------------------------------------------

local function BuildList(page)
    local ui = page.ui
    local left = UI.Inset(page.frame)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(LEFT_WIDTH)

    ui.count = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.count:SetPoint("TOPLEFT", 12, -14)

    ui.scroll = CreateFrame("ScrollFrame", "GuildExpansionUnitScroll", left, "UIPanelScrollFrameTemplate")
    ui.scroll.scrollBarHideable = true
    ui.scroll:SetPoint("TOPLEFT", 8, -40)
    ui.scroll:SetPoint("BOTTOMRIGHT", -28, 40)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.content:SetWidth(LEFT_WIDTH - 36)
    ui.content:SetHeight(1)
    ui.scroll:SetScrollChild(ui.content)

    ui.headers = {}
    for _, key in ipairs({ "units", "troops", "recruits" }) do
        ui.headers[key] = ui.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end

    ui.rows = {}
    for i = 1, MAX_ROWS do
        local r = CreateFrame("Button", nil, ui.content)
        r:SetWidth(LEFT_WIDTH - 40)
        r:SetHeight(ROW_HEIGHT - 4)
        r:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16 })
        r:SetBackdropColor(0.15, 0.12, 0.08, 0.8)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.selected = r:CreateTexture(nil, "BORDER")
        r.selected:SetAllPoints(true)
        r.selected:SetTexture(0.3, 0.5, 0.9, 0.35)

        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetWidth(42)
        r.icon:SetHeight(42)
        r.icon:SetPoint("LEFT", 6, 2)
        r.border = r:CreateTexture(nil, "OVERLAY")
        r.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        r.border:SetBlendMode("ADD")
        r.border:SetWidth(76)
        r.border:SetHeight(76)
        r.border:SetPoint("CENTER", r.icon, "CENTER")
        r.level = r:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        r.level:SetPoint("TOP", r.icon, "BOTTOM", 0, -1)

        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -2)
        r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
        r.bar = CreateFrame("StatusBar", nil, r)
        r.bar:SetWidth(170)
        r.bar:SetHeight(5)
        r.bar:SetPoint("TOPLEFT", r.info, "BOTTOMLEFT", 0, -5)
        r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.bar:SetMinMaxValues(0, 1)
        r.bar.bg = r.bar:CreateTexture(nil, "BACKGROUND")
        r.bar.bg:SetAllPoints(true)
        r.bar.bg:SetTexture(0, 0, 0, 0.6)

        r.role = r:CreateTexture(nil, "ARTWORK")
        r.role:SetWidth(30)
        r.role:SetHeight(30)
        r.role:SetPoint("RIGHT", -6, 0)
        r.role:SetAlpha(0.45)

        r:SetScript("OnClick", function(self)
            selectedId = self.unitId
            page.refresh(page)
        end)
        r:Hide()
        ui.rows[i] = r
    end

    ui.recruitTimer = left:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.recruitTimer:SetPoint("BOTTOMLEFT", 12, 14)
end

local function FillRow(r, u)
    local isCandidate = u.status == 2
    local isTrain = u.train
    local isTroop = not isTrain and GE.IsTroop(u)

    r.unitId = u.id
    r.icon:SetTexture(IconPath(u))
    r.icon:SetDesaturated(isCandidate)
    r.border:SetVertexColor(GE.QualityRGB(u.quality))
    r.level:SetText((isTrain or isTroop) and "" or u.level)
    local ut = GE.unitTemplates[u.template]
    if ut then
        GE.SetRoleIcon(r.role, ut.role)
    else
        r.role:Hide()
    end

    local m = u.status == 1 and MissionOfUnit(u.id)
    if isTrain then
        r.name:SetText("Train " .. u.name)
        r.info:SetText(string.format("|cffffd200%d supplies|r", GE.unitInfo.troopCost))
        r.bar:Hide()
    elseif isCandidate then
        r.name:SetText("|cff9d9d9d" .. u.name .. "|r")
        r.info:SetText(string.format("|cffffd200Recruit: %d supplies|r", u.cost))
        r.bar:Hide()
    elseif m then
        r.name:SetText(isTroop and u.name or ("|cff" .. GE.QualityHex(u.quality) .. u.name .. "|r"))
        local remaining = math.max(0, m.endsAt - GetTime())
        r.info:SetText(remaining > 0 and ("|cffffd200On Mission - " .. UI.FormatDuration(remaining) .. "|r")
            or "|cff80ff80Mission complete|r")
        r.bar:SetStatusBarColor(0.3, 0.6, 1)
        r.bar:SetValue(1 - remaining / math.max(1, m.duration))
        r.bar:Show()
    elseif isTroop then
        r.name:SetText(u.name)
        r.info:SetText(MissionsLeft(u))
        r.bar:Hide()
    else
        r.name:SetText("|cff" .. GE.QualityHex(u.quality) .. u.name .. "|r")
        r.info:SetText("iLvl " .. u.itemLevel)
        r.bar:SetStatusBarColor(0.58, 0.0, 0.55)
        r.bar:SetValue(math.min(1, u.xp / math.max(1, u.xpNext)))
        r.bar:Show()
    end

    if u.id == selectedId then
        r.selected:Show()
    else
        r.selected:Hide()
    end
    r:Show()
end

local function RefreshList(page)
    local ui = page.ui
    local info = GE.unitInfo
    ui.count:SetText(string.format("Units: |cffffffff%d / %d|r     Troops: |cffffffff%d / %d|r",
        info.count, info.max, info.troops, info.maxTroops))

    local y, index = 0, 0
    local function place(key, text)
        local fs = ui.headers[key]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 4, -y)
        fs:SetText(text)
        fs:Show()
        y = y + 20
    end
    local function addRows(list)
        for _, u in ipairs(list) do
            index = index + 1
            local r = ui.rows[index]
            if r then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 0, -y)
                FillRow(r, u)
                y = y + ROW_HEIGHT
            end
        end
    end

    place("units", "Units")
    addRows(GE.units)
    y = y + 6
    place("troops", "Troops")
    addRows(GE.troops)
    addRows(TrainEntries())
    y = y + 6
    if #GE.candidates > 0 then
        place("recruits", "Recruits")
        addRows(GE.candidates)
    else
        ui.headers.recruits:Hide()
    end
    for i = index + 1, #ui.rows do
        ui.rows[i]:Hide()
    end
    ui.content:SetHeight(math.max(1, y))

    ui.recruitTimer:SetText("New recruits in " .. UI.FormatDuration(info.expiresAt - GetTime()))
end

-- Right detail panel -----------------------------------------------------------

local function BuildDetail(page)
    local ui = page.ui
    local right = UI.Inset(page.frame)
    right:SetPoint("TOPLEFT", LEFT_WIDTH + 8, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.right = right

    -- Header: icon, name, description, XP.
    local head = UI.Inset(right)
    head:SetPoint("TOPLEFT", 10, -10)
    head:SetPoint("TOPRIGHT", -10, -10)
    head:SetHeight(76)
    ui.dIcon = head:CreateTexture(nil, "ARTWORK")
    ui.dIcon:SetWidth(48)
    ui.dIcon:SetHeight(48)
    ui.dIcon:SetPoint("LEFT", 12, 4)
    ui.dIconBorder = head:CreateTexture(nil, "OVERLAY")
    ui.dIconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    ui.dIconBorder:SetBlendMode("ADD")
    ui.dIconBorder:SetWidth(88)
    ui.dIconBorder:SetHeight(88)
    ui.dIconBorder:SetPoint("CENTER", ui.dIcon, "CENTER")
    ui.dLevel = head:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    ui.dLevel:SetPoint("TOP", ui.dIcon, "BOTTOM", 0, -2)
    ui.dName = head:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ui.dName:SetPoint("TOPLEFT", ui.dIcon, "TOPRIGHT", 14, 0)
    ui.dDesc = head:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.dDesc:SetPoint("TOPLEFT", ui.dName, "BOTTOMLEFT", 0, -4)
    ui.dXpText = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ui.dXpText:SetPoint("TOPRIGHT", -14, -12)
    ui.dXpLabel = head:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ui.dXpLabel:SetPoint("TOPRIGHT", ui.dXpText, "BOTTOMRIGHT", 0, -2)
    ui.dXp = CreateFrame("StatusBar", nil, head)
    ui.dXp:SetPoint("BOTTOMLEFT", ui.dIcon, "BOTTOMRIGHT", 14, -2)
    ui.dXp:SetPoint("RIGHT", head, "RIGHT", -14, 0)
    ui.dXp:SetHeight(8)
    ui.dXp:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ui.dXp:SetStatusBarColor(0.58, 0.0, 0.55)
    ui.dXp:SetMinMaxValues(0, 1)
    ui.dXp.bg = ui.dXp:CreateTexture(nil, "BACKGROUND")
    ui.dXp.bg:SetAllPoints(true)
    ui.dXp.bg:SetTexture(0, 0, 0, 0.6)

    -- Large portrait (in place of Legion's 3D model).
    ui.dPortrait = right:CreateTexture(nil, "ARTWORK")
    ui.dPortrait:SetWidth(150)
    ui.dPortrait:SetHeight(150)
    ui.dPortrait:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 50, -40)
    ui.dPortraitBorder = right:CreateTexture(nil, "OVERLAY")
    ui.dPortraitBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    ui.dPortraitBorder:SetBlendMode("ADD")
    ui.dPortraitBorder:SetWidth(270)
    ui.dPortraitBorder:SetHeight(270)
    ui.dPortraitBorder:SetPoint("CENTER", ui.dPortrait, "CENTER")
    ui.dItemLevel = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.dItemLevel:SetPoint("TOP", ui.dPortrait, "BOTTOM", 0, -16)
    ui.dStatus = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.dStatus:SetPoint("TOP", ui.dItemLevel, "BOTTOM", 0, -6)
    ui.dStatus:SetWidth(240)

    -- Role, abilities and traits.
    local colX = 280
    ui.dRoleHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.dRoleHeader:SetPoint("TOPLEFT", head, "BOTTOMLEFT", colX, -24)
    ui.dRoleHeader:SetText("Role")
    ui.dRoleIcon = right:CreateTexture(nil, "ARTWORK")
    ui.dRoleIcon:SetWidth(28)
    ui.dRoleIcon:SetHeight(28)
    ui.dRoleIcon:SetPoint("TOPLEFT", ui.dRoleHeader, "BOTTOMLEFT", 0, -6)
    ui.dRole = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    ui.dRole:SetPoint("LEFT", ui.dRoleIcon, "RIGHT", 8, 0)

    ui.dAbilityHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.dAbilityHeader:SetPoint("TOPLEFT", ui.dRoleIcon, "BOTTOMLEFT", 0, -18)
    ui.dAbilityHeader:SetText("Abilities")
    ui.dAbilities = {}
    for i = 1, 2 do
        local a = UI.IconButton(right, 34)
        a:SetPoint("TOPLEFT", ui.dAbilityHeader, "BOTTOMLEFT", 0, -8 - (i - 1) * 44)
        a.name = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        a.name:SetPoint("TOPLEFT", a, "TOPRIGHT", 10, -1)
        a.sub = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        a.sub:SetPoint("TOPLEFT", a.name, "BOTTOMLEFT", 0, -3)
        ui.dAbilities[i] = a
    end

    ui.dTraitHeader = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.dTraitHeader:SetPoint("TOPLEFT", ui.dAbilityHeader, "BOTTOMLEFT", 0, -102)
    ui.dTraitHeader:SetText("Traits")
    ui.dTraits = {}
    for i = 1, 2 do
        local t = UI.IconButton(right, 34)
        t:SetPoint("TOPLEFT", ui.dTraitHeader, "BOTTOMLEFT", 0, -8 - (i - 1) * 44)
        t.name = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        t.name:SetPoint("TOPLEFT", t, "TOPRIGHT", 10, -1)
        t.sub = right:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t.sub:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
        t.sub:SetWidth(240)
        t.sub:SetJustifyH("LEFT")
        ui.dTraits[i] = t
    end
    ui.dNoTraits = right:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    ui.dNoTraits:SetPoint("TOPLEFT", ui.dTraitHeader, "BOTTOMLEFT", 0, -10)
    ui.dNoTraits:SetWidth(300)
    ui.dNoTraits:SetJustifyH("LEFT")

    -- Equipment: drag gear from the bags onto a slot. The item is used up.
    ui.dEquip = CreateFrame("Frame", nil, right)
    ui.dEquip:SetWidth(220)
    ui.dEquip:SetHeight(90)
    ui.dEquip:SetPoint("BOTTOMLEFT", 20, 14)
    ui.dEquipHeader = ui.dEquip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.dEquipHeader:SetPoint("TOPLEFT", 4, 0)
    ui.dEquipHeader:SetText("Equipment")

    local function GiveFromCursor(slotButton)
        local kind, itemId, link = GetCursorInfo()
        if kind ~= "item" then
            return
        end
        local u = selectedId and FindEntry(selectedId)
        local fromBags = lastPickup and GetContainerItemLink(lastPickup.bag, lastPickup.slot)
        ClearCursor()
        if not u or u.train or u.status == 2 or GE.IsTroop(u) then
            return
        end
        if not fromBags or tonumber(fromBags:match("item:(%d+)")) ~= itemId then
            UIErrorsFrame:AddMessage("Drag the item from your bags.", 1.0, 0.1, 0.1, 1.0)
            return
        end
        local dialog = StaticPopup_Show("GUILDEXPANSION_GIVE_GEAR", link or "this item", u.name)
        if dialog then
            dialog.data = { unit = u.id, key = slotButton.key, bag = lastPickup.bag, slot = lastPickup.slot }
        end
    end

    ui.dGear = {}
    for i, def in ipairs({ { key = "W", label = "Weapon" }, { key = "A", label = "Armor" }, { key = "E", label = "Effect" } }) do
        local b = UI.IconButton(ui.dEquip, 40)
        b:SetPoint("TOPLEFT", ui.dEquipHeader, "BOTTOMLEFT", 4 + (i - 1) * 66, -8)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        b.bg:SetWidth(66)
        b.bg:SetHeight(66)
        b.bg:SetPoint("CENTER")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.label = ui.dEquip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
        b.label:SetText(def.label)
        b.key = def.key
        b:SetScript("OnReceiveDrag", GiveFromCursor)
        b:SetScript("OnClick", GiveFromCursor)
        ui.dGear[i] = b
    end

    ui.dAction = UI.Button(right, "Dismiss", 160, 28)
    ui.dAction:SetPoint("BOTTOMRIGHT", -16, 16)
    ui.dActionNote = right:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ui.dActionNote:SetPoint("RIGHT", ui.dAction, "LEFT", -14, 0)

    ui.dEmpty = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ui.dEmpty:SetPoint("CENTER")
end

local function SetAbilityRow(b, id)
    local a = GE.ABILITIES[id or 0]
    if a then
        b.icon:SetTexture("Interface\\Icons\\" .. a.icon)
        b.name:SetText(a.name)
        b.sub:SetText("Counters: " .. a.threat)
        b.tooltip = function()
            GameTooltip:AddLine(a.name)
            GameTooltip:AddLine("Counters the " .. a.threat .. " threat on missions.", 1, 1, 1, true)
        end
        b:Show(); b.name:Show(); b.sub:Show()
    else
        b:Hide(); b.name:Hide(); b.sub:Hide()
    end
end

local function RefreshDetail(page)
    local ui = page.ui
    local u = selectedId and FindEntry(selectedId)
    local shown = u ~= nil
    for _, region in ipairs({ ui.dPortrait, ui.dPortraitBorder, ui.dItemLevel, ui.dStatus, ui.dRoleHeader, ui.dRoleIcon,
                              ui.dRole, ui.dAbilityHeader, ui.dTraitHeader, ui.dNoTraits, ui.dEquipHeader, ui.dEquip,
                              ui.dAction, ui.dActionNote, ui.dIcon, ui.dIconBorder, ui.dLevel, ui.dName, ui.dDesc,
                              ui.dXpText, ui.dXpLabel, ui.dXp }) do
        if shown then
            region:Show()
        else
            region:Hide()
        end
    end
    if not shown then
        for _, b in ipairs(ui.dAbilities) do b:Hide(); b.name:Hide(); b.sub:Hide() end
        for _, b in ipairs(ui.dTraits) do b:Hide(); b.name:Hide(); b.sub:Hide() end
        local info = GE.unitInfo
        ui.dEmpty:SetText(info.status == 1 and "Join a guild to recruit units."
            or (info.status == 2 and "Units are turned off on this server." or "Select a unit."))
        return
    end
    ui.dEmpty:SetText("")

    local isTrain = u.train
    local isTroop = isTrain or GE.IsTroop(u)
    local isCandidate = u.status == 2
    local ut = GE.unitTemplates[u.template]
    local path = IconPath(u)
    local supplies = GE.state and GE.state.supplies or 0

    ui.dIcon:SetTexture(path)
    ui.dIconBorder:SetVertexColor(GE.QualityRGB(u.quality))
    ui.dPortrait:SetTexture(path)
    ui.dPortrait:SetDesaturated(isCandidate)
    ui.dPortraitBorder:SetVertexColor(GE.QualityRGB(u.quality))
    if ut then
        GE.SetRoleIcon(ui.dRoleIcon, ut.role)
        ui.dRole:SetText(GE.ROLES[ut.role] and GE.ROLES[ut.role].name or "")
    end

    if isTroop then
        ui.dLevel:SetText("")
        ui.dName:SetText(u.name)
        ui.dDesc:SetText("Troop  -  " .. (ut and GE.ROLES[ut.role] and GE.ROLES[ut.role].name or ""))
        ui.dXpText:SetText("")
        ui.dXpLabel:SetText("")
        ui.dXp:Hide()
        ui.dItemLevel:SetText(isTrain and "Troop" or MissionsLeft(u))
        ui.dEquipHeader:Hide()
        ui.dEquip:Hide()
        -- A troop type shows the ability its troops will have.
        SetAbilityRow(ui.dAbilities[1], isTrain and ut and ut.abilities and ut.abilities[1] or u.abilities[1])
        SetAbilityRow(ui.dAbilities[2], nil)
        for _, b in ipairs(ui.dTraits) do b:Hide(); b.name:Hide(); b.sub:Hide() end
        ui.dTraitHeader:Hide()
        ui.dNoTraits:SetText("Troops fill a mission slot, count for their role and counter one threat. "
            .. "They wear out after a few missions and die on lethal missions.")
        ui.dNoTraits:ClearAllPoints()
        ui.dNoTraits:SetPoint("TOPLEFT", ui.dAbilityHeader, "BOTTOMLEFT", 0, -60)
    else
        ui.dTraitHeader:Show()
        ui.dNoTraits:ClearAllPoints()
        ui.dNoTraits:SetPoint("TOPLEFT", ui.dTraitHeader, "BOTTOMLEFT", 0, -10)
        ui.dLevel:SetText(u.level)
        ui.dName:SetText("|cff" .. GE.QualityHex(u.quality) .. u.name .. "|r")
        ui.dDesc:SetText(string.format("Level %d %s  -  %s", u.level, GE.UnitDescription(u), GE.QUALITY_NAMES[u.quality] or ""))
        if isCandidate then
            ui.dXpText:SetText("")
            ui.dXpLabel:SetText("")
            ui.dXp:Hide()
        elseif u.level >= GE.unitInfo.cap and u.quality < 4 and u.promoNext > 0 then
            ui.dXpText:SetText(string.format("|cffa335ee%s / %s XP|r", GE.FormatNumber(u.promoXp), GE.FormatNumber(u.promoNext)))
            ui.dXpLabel:SetText("to promotion (" .. GE.QUALITY_NAMES[u.quality + 1] .. ")")
            ui.dXp:SetValue(math.min(1, u.promoXp / math.max(1, u.promoNext)))
        elseif u.level >= GE.unitInfo.cap then
            ui.dXpText:SetText("Level cap")
            ui.dXpLabel:SetText("Levels with your highest character")
            ui.dXp:SetValue(1)
        else
            ui.dXpText:SetText(GE.FormatNumber(math.max(0, u.xpNext - u.xp)) .. " XP")
            ui.dXpLabel:SetText("to next level")
            ui.dXp:SetValue(math.min(1, u.xp / math.max(1, u.xpNext)))
        end
        ui.dItemLevel:SetText("Item Level " .. u.itemLevel)
        if isCandidate then
            ui.dEquip:Hide()
        else
            ui.dEquip:Show()
            local armorName = ut and GE.ARMOR_NAMES[ut.armor] or "matching"
            local roleWeapons = ut and ({ [0] = "a one-handed weapon or shield", [1] = "a staff, mace or wand", [2] = "any weapon" })[ut.role] or "a weapon"
            local gear = {
                { item = u.weaponItem, ilvl = u.weaponIlvl, empty = "Weapon: drag " .. roleWeapons .. " here." },
                { item = u.armorItem, ilvl = u.armorIlvl, empty = "Armor: drag a " .. string.lower(armorName) .. " armor piece here." },
                { item = u.effectItem, effect = GE.UNIT_EFFECTS[u.effectKind],
                  empty = "Effect: drag a trinket, ring, necklace, or a crafted bag or gadget here." },
            }
            for i, b in ipairs(ui.dGear) do
                local g = gear[i]
                if g.item > 0 then
                    b.icon:SetTexture(GE.ItemIcon(g.item))
                    b.icon:Show()
                    local _, _, quality = GetItemInfo(g.item)
                    UI.SetBorderQuality(b, quality or 2)
                else
                    b.icon:Hide()
                    b.border:Hide()
                end
                b.tooltip = function()
                    if g.item > 0 then
                        GameTooltip:SetHyperlink("item:" .. g.item)
                        if g.effect then
                            GameTooltip:AddLine(g.effect.name .. ": " .. g.effect.desc, 0, 1, 0, true)
                        else
                            GameTooltip:AddLine("Counts as item level " .. g.ilvl .. " for this unit.", 0, 1, 0, true)
                        end
                        GameTooltip:AddLine("Drag another item here to replace it.", 0.8, 0.8, 0.8, true)
                    else
                        GameTooltip:AddLine(g.empty, 1, 1, 1, true)
                        if i < 3 then
                            GameTooltip:AddLine("Enchants add 5 item levels, each gem 3. The item is used up.", 0.8, 0.8, 0.8, true)
                        else
                            for k = 1, 7 do
                                local e = GE.UNIT_EFFECTS[k]
                                GameTooltip:AddLine("|cffffd200" .. e.name .. ":|r " .. e.desc, 1, 1, 1, true)
                            end
                        end
                    end
                end
            end
            if u.weaponIlvl > 0 or u.armorIlvl > 0 then
                ui.dItemLevel:SetText(string.format("Item Level %d  |cffaaaaaa(weapon %s, armor %s)|r", u.itemLevel,
                    u.weaponIlvl > 0 and u.weaponIlvl or "-", u.armorIlvl > 0 and u.armorIlvl or "-"))
            end
        end
        for i, b in ipairs(ui.dAbilities) do
            SetAbilityRow(b, u.abilities[i])
        end
        local anyTrait = false
        for i, b in ipairs(ui.dTraits) do
            local t = GE.TRAITS[u.traits[i] or 0]
            if t then
                anyTrait = true
                b.icon:SetTexture("Interface\\Icons\\" .. t.icon)
                b.name:SetText(t.name)
                b.sub:SetText(t.desc)
                b.tooltip = function()
                    GameTooltip:AddLine(t.name)
                    GameTooltip:AddLine(t.desc, 1, 1, 1, true)
                end
                b:Show(); b.name:Show(); b.sub:Show()
            else
                b:Hide(); b.name:Hide(); b.sub:Hide()
            end
        end
        ui.dNoTraits:SetText(anyTrait and "" or "No traits. Rare and epic units have traits.")
    end

    local m = u.status == 1 and MissionOfUnit(u.id)
    if isTrain then
        ui.dStatus:SetText("Trains instantly. Each troop lasts 2 missions.")
    elseif m then
        local remaining = math.max(0, m.endsAt - GetTime())
        ui.dStatus:SetText(remaining > 0 and ("|cffffd200On a mission - " .. UI.FormatDuration(remaining) .. " left|r")
            or "|cff80ff80Mission complete - collect it on the Missions tab|r")
    elseif isCandidate then
        ui.dStatus:SetText("|cffaaaaaaAvailable to recruit|r")
    else
        ui.dStatus:SetText("|cff80ff80Ready for a mission|r")
    end

    if isTrain then
        local info = GE.unitInfo
        local full = info.troops >= info.maxTroops
        ui.dAction:SetText("Train")
        ui.dAction:SetScript("OnClick", function() GE.Send("TROOP " .. u.template) end)
        ui.dActionNote:SetText(full and "|cffff4040No room for more troops.|r"
            or string.format("Cost: %s%d supplies|r", supplies >= info.troopCost and "|cffffd200" or "|cffff4040", info.troopCost))
        if not full and supplies >= info.troopCost then
            ui.dAction:Enable()
        else
            ui.dAction:Disable()
        end
    elseif isCandidate then
        local full = GE.unitInfo.count >= GE.unitInfo.max
        ui.dAction:SetText("Recruit")
        ui.dAction:SetScript("OnClick", function() GE.Send("RECRUIT " .. u.id) end)
        ui.dActionNote:SetText(full and "|cffff4040Your roster is full.|r"
            or string.format("Cost: %s%d supplies|r", supplies >= u.cost and "|cffffd200" or "|cffff4040", u.cost))
        if not full and supplies >= u.cost then
            ui.dAction:Enable()
        else
            ui.dAction:Disable()
        end
    else
        ui.dAction:SetText("Dismiss")
        ui.dAction:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("GUILDEXPANSION_DISMISS_UNIT", u.name)
            if dialog then
                dialog.data = u.id
            end
        end)
        ui.dActionNote:SetText("")
        if u.status == 1 then
            ui.dAction:Disable()
        else
            ui.dAction:Enable()
        end
    end
end

-- Page ------------------------------------------------------------------------

local function Build(page)
    thePage = page
    page.ui = {}
    BuildList(page)
    BuildDetail(page)

    page.frame:SetScript("OnShow", function()
        GE.RequestUnits()
        GE.RequestMissions()
    end)
    local elapsedSince = 0
    page.frame:SetScript("OnUpdate", function(self, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince >= 1 then
            elapsedSince = 0
            page.refresh(page)
        end
    end)
end

local function Refresh(page)
    if not selectedId or not FindEntry(selectedId) then
        local first = GE.units[1] or GE.candidates[1]
        selectedId = first and first.id or nil
    end
    RefreshList(page)
    RefreshDetail(page)
end

UI.RegisterPage("units", "Units", "Guild Units", Build, Refresh)
