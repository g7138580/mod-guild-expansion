--[[
  Guild Expansion: the options page (Interface > AddOns > Guild Expansion): alerts, the
  minimap and Guild frame buttons, the Guild tab summary, the key that opens the window,
  and the window's size and position. The window's Options button, right-clicking the
  minimap button and /gl options all open it.
]]

local GE = GuildExpansion

local panel = CreateFrame("Frame", "GuildExpansionOptions", UIParent)
panel.name = "Guild Expansion"
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Guild Expansion")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -32, 0)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("Guild levels and perks, work orders, contracts, the quartermaster, units and missions.")

local checks = {}
local function Checkbox(key, label, anchor)
    local name = "GuildExpansionOption_" .. key
    local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    _G[name .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self) GE.SetOption(key, self:GetChecked() and true or false) end)
    cb.key = key
    checks[#checks + 1] = cb
    return cb
end

local function Header(text, anchor, gap)
    local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if anchor then
        h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 14))
    end
    h:SetText(text)
    return h
end

local function Button(label, width, onClick)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetWidth(width)
    b:SetHeight(22)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- Alerts.
local alerts = Header("Alerts", subtitle, 20)
local levelAlert = Checkbox("levelAlert", "Show a banner when the guild levels up", alerts)
local xpText = Checkbox("xpText", "Show guild XP gains on screen", levelAlert)
local toasts = Checkbox("toasts", "Show an alert when a mission or contract is done", xpText)
local progress = Checkbox("contractProgress", "Show contract progress on screen", toasts)
local notice = Checkbox("contractNotice", "Announce new contracts in chat", progress)

-- Buttons.
local buttons = Header("Buttons", notice)
local minimap = Checkbox("minimapButton", "Show the minimap button", buttons)
local guildTab = Checkbox("guildTab", "Show the tab on the Guild window", minimap)

-- Guild tab.
local guildHeader = Header("Guild tab", guildTab)
local summary = Checkbox("summary", "Show what's ready (contracts, missions, orders)", guildHeader)

-- Key, in the right-hand column.
local keyHeader = Header("Key")
keyHeader:SetPoint("TOPLEFT", alerts, "TOPLEFT", 344, 0)
local keyText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
keyText:SetPoint("TOPLEFT", keyHeader, "BOTTOMLEFT", 4, -10)

local changeKey = Button("Change key", 110, function()
    -- The key binding window; the window is listed under its own Guild Expansion header.
    InterfaceOptionsFrame:Hide()
    if KeyBindingFrame_LoadUI then
        KeyBindingFrame_LoadUI()
    end
    if KeyBindingFrame then
        ShowUIPanel(KeyBindingFrame)
    end
end)
changeKey:SetPoint("TOPLEFT", keyText, "BOTTOMLEFT", -4, -8)

local clearKey = Button("Clear key", 90, function()
    local key1, key2 = GetBindingKey("GUILDEXPANSION_TOGGLE")
    if key1 then
        SetBinding(key1)
    end
    if key2 then
        SetBinding(key2)
    end
    SaveBindings(GetCurrentBindingSet())
    panel.refresh()
end)
clearKey:SetPoint("LEFT", changeKey, "RIGHT", 6, 0)

local defaultKey = Button("Use " .. GetBindingText(GE.DEFAULT_KEY, "KEY_"), 120, function()
    local action = GetBindingAction(GE.DEFAULT_KEY)
    if action and action ~= "" and action ~= "GUILDEXPANSION_TOGGLE" then
        GE.Print(GetBindingText(GE.DEFAULT_KEY, "KEY_") .. " is already used by something else; pick another with Change key.")
        return
    end
    SetBinding(GE.DEFAULT_KEY, "GUILDEXPANSION_TOGGLE")
    SaveBindings(GetCurrentBindingSet())
    panel.refresh()
end)
defaultKey:SetPoint("TOPLEFT", changeKey, "BOTTOMLEFT", 0, -6)

-- Window.
local windowHeader = Header("Window", defaultKey, 20)

local slider = CreateFrame("Slider", "GuildExpansionOptionScale", panel, "OptionsSliderTemplate")
slider:SetWidth(200)
slider:SetPoint("TOPLEFT", windowHeader, "BOTTOMLEFT", 4, -20)
slider:SetMinMaxValues(0.6, 1.4)
slider:SetValueStep(0.05)
GuildExpansionOptionScaleLow:SetText("60%")
GuildExpansionOptionScaleHigh:SetText("140%")
slider:SetScript("OnValueChanged", function(self, value)
    GuildExpansionOptionScaleText:SetText(string.format("Window size: %d%%", math.floor(value * 100 + 0.5)))
    if not self.updating then
        GE.SetScale(value)
    end
end)

local open = Button("Open the window", 130, function()
    InterfaceOptionsFrame:Hide()
    GE.UI.Show()
end)
open:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", -4, -24)

local reset = Button("Reset position", 120, function()
    GE.UI.ResetPosition()
    GE.Print("window position reset.")
end)
reset:SetPoint("LEFT", open, "RIGHT", 6, 0)

function panel.refresh()
    for _, cb in ipairs(checks) do
        cb:SetChecked(GE.Options()[cb.key] and true or false)
    end
    local key = GE.KeyText()
    keyText:SetText("Open the window with: " .. (key and ("|cffffd200" .. key .. "|r") or "|cff999999not bound|r"))
    slider.updating = true
    slider:SetValue(GE.Options().scale or 1)
    slider.updating = false
end

panel:SetScript("OnShow", panel.refresh)
GE.RegisterListener(function(event)
    if event == "state" and panel:IsShown() then
        panel.refresh()
    end
end)

InterfaceOptions_AddCategory(panel)

function GE.OpenOptions()
    -- 3.3.5 often opens the AddOns list on the first call instead of the page; the second lands.
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
