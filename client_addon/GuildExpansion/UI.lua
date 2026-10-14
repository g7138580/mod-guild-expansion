--[[
  Guild Expansion: the main window (Legion mission-table style), shared widgets, and the
  side tab on the Guild frame. Pages (Missions, Units, Work Orders, Guild) register
  themselves and draw into the content area.
]]

local GE = GuildExpansion

local UI = {}
GE.UI = UI

local WIDTH, HEIGHT = 940, 640
UI.CONTENT_WIDTH = WIDTH - 36
UI.CONTENT_HEIGHT = HEIGHT - 54

local pages = {}        -- { name, label, title, build, refresh, frame, tab }
local frame
local title
local supplies
local current

-- Shared widgets -----------------------------------------------------------

function UI.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if d > 0 then
        return h > 0 and string.format("%dd %dh", d, h) or string.format("%d day%s", d, d == 1 and "" or "s")
    end
    if h > 0 then
        return m > 0 and string.format("%dh %dm", h, m) or string.format("%d hr", h)
    end
    if m > 0 then
        return string.format("%d min", m)
    end
    return string.format("%ds", seconds % 60)
end

function UI.Button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(height or 22)
    b:SetText(label)
    return b
end

-- Dark recessed panel with a thin border.
function UI.Inset(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.55)
    f:SetBackdropBorderColor(0.55, 0.45, 0.3)
    return f
end

-- Parchment-backed clickable row, like the Legion mission list.
function UI.ParchmentRow(parent, width, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(width)
    row:SetHeight(height)
    row:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    row:SetBackdropBorderColor(0.6, 0.5, 0.35)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetPoint("TOPLEFT", 3, -3)
    row.bg:SetPoint("BOTTOMRIGHT", -3, 3)
    row.bg:SetTexture("Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal")
    row.bg:SetVertexColor(0.42, 0.36, 0.28)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    return row
end

-- Square icon button with a count and a colored border (rewards, item slots).
function UI.IconButton(parent, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(size)
    b:SetHeight(size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(true)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetWidth(size * 1.8)
    b.border:SetHeight(size * 1.8)
    b.border:SetPoint("CENTER")
    b.border:Hide()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            self.tooltip(self)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

function UI.SetBorderQuality(button, quality)
    if quality and quality >= 2 then
        local r, g, b = GetItemQualityColor(quality)
        button.border:SetVertexColor(r, g, b)
        button.border:Show()
    else
        button.border:Hide()
    end
end

local REWARD_ICONS = {
    gold = "INV_Misc_Coin_02",
    guildXp = "Achievement_Level_10",
    supplies = "INV_Crate_01",
    unitXp = "Spell_Holy_HolyGuidance",
    gear = "INV_Chest_Chain_05",
}
local GEAR_NAMES = { [2] = "Uncommon gear", [3] = "Rare gear", [4] = "Epic gear" }

-- Fills reward buttons from a mission or order table; returns the number used.
function UI.FillRewards(buttons, r)
    local list = {}
    if (r.gold or 0) > 0 then
        list[#list + 1] = { icon = REWARD_ICONS.gold, count = r.gold >= 10000 and math.floor(r.gold / 10000) or "",
            tip = function() GameTooltip:AddLine("Gold"); GameTooltip:AddLine(GE.FormatMoney(r.gold), 1, 1, 1) end }
    end
    if (r.guildXp or 0) > 0 then
        list[#list + 1] = { icon = REWARD_ICONS.guildXp, count = "",
            tip = function() GameTooltip:AddLine("Guild Experience"); GameTooltip:AddLine(GE.FormatNumber(r.guildXp) .. " guild XP", 0.3, 0.65, 1) end }
    end
    if (r.supplies or 0) > 0 then
        list[#list + 1] = { icon = REWARD_ICONS.supplies, count = r.supplies,
            tip = function() GameTooltip:AddLine("Guild Supplies"); GameTooltip:AddLine(r.supplies .. " supplies", 1, 0.82, 0) end }
    end
    if (r.item or 0) > 0 and (r.itemCount or 0) > 0 then
        list[#list + 1] = { icon = GE.ItemIcon(r.item), count = r.itemCount, item = r.item,
            tip = function() GameTooltip:SetHyperlink("item:" .. r.item) end }
    end
    if (r.gear or 0) > 0 then
        list[#list + 1] = { icon = REWARD_ICONS.gear, count = "", quality = r.gear,
            tip = function()
                GameTooltip:AddLine("|cff" .. GE.QualityHex(r.gear) .. GEAR_NAMES[r.gear] .. "|r")
                GameTooltip:AddLine("A piece of gear for the character who collects the mission.", 1, 1, 1, true)
            end }
    end
    if (r.unitXp or 0) > 0 then
        list[#list + 1] = { icon = REWARD_ICONS.unitXp, count = "",
            tip = function() GameTooltip:AddLine("Unit Experience"); GameTooltip:AddLine(GE.FormatNumber(r.unitXp) .. " XP for each unit sent", 0.8, 0.53, 1) end }
    end

    for i, b in ipairs(buttons) do
        local e = list[i]
        if e then
            b.icon:SetTexture(e.icon:find("\\") and e.icon or ("Interface\\Icons\\" .. e.icon))
            b.count:SetText(e.count)
            UI.SetBorderQuality(b, e.quality)
            b.tooltip = e.tip
            b:Show()
        else
            b:Hide()
        end
    end
    return math.min(#list, #buttons)
end

-- Item info the client hasn't cached yet is requested through a hidden tooltip.
local cacheTooltip = CreateFrame("GameTooltip", "GuildExpansionCacheTooltip", UIParent, "GameTooltipTemplate")

function GE.ItemIcon(itemId)
    local icon = GetItemIcon and GetItemIcon(itemId)
    if not icon then
        icon = select(10, GetItemInfo(itemId))
    end
    if not icon then
        cacheTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        cacheTooltip:SetHyperlink("item:" .. itemId)
        cacheTooltip:Hide()
    end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Pages ------------------------------------------------------------------

function UI.RegisterPage(name, label, windowTitle, build, refresh)
    pages[#pages + 1] = { name = name, label = label, title = windowTitle, build = build, refresh = refresh }
end

function UI.IsShowingPage(name)
    return frame and frame:IsShown() and current and current.name == name
end

local function RefreshChrome()
    if current then
        title:SetText(current.title)
    end
    local st = GE.state
    supplies.value:SetText(GE.FormatNumber(st and st.supplies or 0))
end

local function SelectPage(name)
    for i, page in ipairs(pages) do
        if page.name == name then
            current = page
            page.frame:Show()
            PanelTemplates_SetTab(frame, i)
        else
            page.frame:Hide()
        end
    end
    RefreshChrome()
    if current then
        current.refresh(current)
    end
end

function UI.ApplyScale()
    if frame then
        frame:SetScale(GE.Options().scale or 1)
    end
end

local function BuildFrame()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "GuildExpansionFrame", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetHeight(HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnShow", function()
        GE.RequestSync()
        PlaySound("igCharacterInfoOpen")
    end)
    frame:SetScript("OnHide", function()
        PlaySound("igCharacterInfoClose")
    end)
    frame:Hide()
    tinsert(UISpecialFrames, "GuildExpansionFrame")

    local header = frame:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetWidth(400)
    header:SetHeight(64)
    header:SetPoint("TOP", 0, 12)
    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)

    -- Guild tabard badge in the top-left corner. Sizes follow the standard minimap button
    -- (31px button, 53px tracking border, 17px icon at 7,-6) scaled by 2.
    local badge = CreateFrame("Frame", nil, frame)
    badge:SetWidth(62)
    badge:SetHeight(62)
    badge:SetPoint("TOPLEFT", -14, 14)
    badge:SetFrameLevel(frame:GetFrameLevel() + 5)
    local backing = badge:CreateTexture(nil, "BACKGROUND")
    backing:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    backing:SetWidth(40)
    backing:SetHeight(40)
    backing:SetPoint("TOPLEFT", 14, -10)
    local portrait = badge:CreateTexture(nil, "ARTWORK")
    portrait:SetWidth(36)
    portrait:SetHeight(36)
    portrait:SetPoint("TOPLEFT", 15, -11)
    if SetPortraitToTexture then
        SetPortraitToTexture(portrait, "Interface\\Icons\\INV_Shirt_GuildTabard_01")
    else
        portrait:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    end
    local ring = badge:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetWidth(106)
    ring:SetHeight(106)
    ring:SetPoint("TOPLEFT", 0, 0)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- Guild Supplies, top right, like "Your Resources".
    supplies = UI.Inset(frame)
    supplies:SetWidth(220)
    supplies:SetHeight(26)
    supplies:SetPoint("TOPRIGHT", -36, -12)
    supplies.label = supplies:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    supplies.label:SetPoint("LEFT", 10, 0)
    supplies.label:SetText("Guild Supplies")
    supplies.icon = supplies:CreateTexture(nil, "ARTWORK")
    supplies.icon:SetWidth(18)
    supplies.icon:SetHeight(18)
    supplies.icon:SetPoint("RIGHT", -6, 0)
    supplies.icon:SetTexture("Interface\\Icons\\INV_Crate_01")
    supplies.value = supplies:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    supplies.value:SetPoint("RIGHT", supplies.icon, "LEFT", -6, 0)
    supplies:EnableMouse(true)
    supplies:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Guild Supplies")
        GameTooltip:AddLine("Earned from work orders, contracts and missions. Spent to start missions and recruit units.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    supplies:SetScript("OnLeave", function() GameTooltip:Hide() end)

    for i, page in ipairs(pages) do
        page.frame = CreateFrame("Frame", nil, frame)
        page.frame:SetPoint("TOPLEFT", 18, -44)
        page.frame:SetPoint("BOTTOMRIGHT", -18, 16)
        page.frame:Hide()
        page.build(page)

        local tab = CreateFrame("Button", "GuildExpansionFrameTab" .. i, frame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(page.label)
        if i == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 16, 8)
        else
            tab:SetPoint("LEFT", "GuildExpansionFrameTab" .. (i - 1), "RIGHT", -15, 0)
        end
        tab:SetScript("OnClick", function()
            PlaySound("igCharacterInfoTab")
            SelectPage(page.name)
        end)
        PanelTemplates_TabResize(tab, 0)
        page.tab = tab
    end
    PanelTemplates_SetNumTabs(frame, #pages)
    UI.ApplyScale()
end

function UI.Show(name)
    BuildFrame()
    frame:Show()
    SelectPage(name or (current and current.name) or pages[1].name)
end

function UI.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        UI.Show()
    end
end

GE.RegisterListener(function()
    if not frame or not frame:IsShown() then
        return
    end
    RefreshChrome()
    if current then
        current.refresh(current)
    end
end)

-- Side tab on the Guild frame (Social > Guild), like the spellbook's tabs.
local function BuildGuildTab()
    if not GuildFrame or GuildExpansionGuildTab then
        return
    end

    local tab = CreateFrame("CheckButton", "GuildExpansionGuildTab", GuildFrame)
    tab:SetWidth(32)
    tab:SetHeight(32)
    tab:SetPoint("TOPLEFT", GuildFrame, "TOPRIGHT", -32, -65)

    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    bg:SetWidth(64)
    bg:SetHeight(64)
    bg:SetPoint("TOPLEFT", -3, 11)

    tab:SetNormalTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")

    tab:SetScript("OnClick", function(self)
        self:SetChecked(false)
        UI.Toggle()
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Guild Expansion")
        local st = GE.state
        if st then
            GameTooltip:AddLine(string.format("Guild level %d", st.level), 1, 1, 1)
            if st.level < GE.MAX_LEVEL and st.nextXp > st.prev then
                local pct = (st.xp - st.prev) / (st.nextXp - st.prev) * 100
                GameTooltip:AddLine(string.format("%.0f%% to level %d", pct, st.level + 1), 0.8, 0.8, 0.8)
            end
        end
        GameTooltip:AddLine("Click to open missions, units, work orders and perks.", 0, 1, 0, true)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", BuildGuildTab)
