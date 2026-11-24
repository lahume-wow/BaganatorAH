local ADDON_NAME, ns = ...
local L = ns.L

------------------------------------------------------------------------
-- Fenêtre d'options (clic droit sur un bouton Scan HV, ou /bah options)
------------------------------------------------------------------------
local FRAME_NAME = "BaganatorAHOptionsFrame"
local WIDTH, HEIGHT = 440, 556
local ROWS, ROW_H = 7, 22
local QUESTION_ICON = 134400 -- Interface\Icons\INV_Misc_QuestionMark

local frame
local refreshers = {}
local listOffset = 0

-- Noms de rareté : ceux du jeu (déjà traduits), sinon l'anglais.
local QUALITY_FALLBACK = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local function DB() return BaganatorAHDB end

local function QualityName(q)
  return _G["ITEM_QUALITY" .. q .. "_DESC"] or QUALITY_FALLBACK[q]
end

local function QualityColor(q)
  local getColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
  if getColor then
    local ok, r, g, b = pcall(getColor, q)
    if ok and r then return r, g, b end
  end
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function ItemIcon(itemID)
  local fn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if fn then
    local ok, icon = pcall(fn, itemID)
    if ok and icon then return icon end
  end
  return QUESTION_ICON
end

local function ItemNameByID(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local name = C_Item.GetItemNameByID(itemID)
    if name then return name end
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
  end
end

local function Trim(text)
  local s = (text or ""):gsub("^%s+", "")
  s = s:gsub("%s+$", "")
  return s
end

------------------------------------------------------------------------
-- Petits constructeurs
------------------------------------------------------------------------
local function Header(parent, text, y)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", 16, y)
  fs:SetText(text)
  return fs
end

local function Hint(parent, text, y, x)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  fs:SetPoint("TOPLEFT", x or 18, y)
  fs:SetText(text)
  return fs
end

-- Case à cocher. get() renvoie l'état, set(bool) l'enregistre.
local function Check(parent, label, x, y, get, set, color, tooltip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y)

  local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  fs:SetText(label)
  if color then fs:SetTextColor(color[1], color[2], color[3]) end
  cb.label = fs

  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    for _, refresh in ipairs(refreshers) do refresh() end
  end)
  if tooltip then
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(label, 1, 1, 1)
      GameTooltip:AddLine(tooltip, nil, nil, nil, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  refreshers[#refreshers + 1] = function() cb:SetChecked(get() and true or false) end
  frame.checks[#frame.checks + 1] = cb
  return cb
end

------------------------------------------------------------------------
-- Liste des objets exclus
------------------------------------------------------------------------
local RefreshList

local function EntryLabel(entry)
  if entry.id then
    local name = ItemNameByID(entry.id)
    return (name or (L.ITEM .. " #" .. entry.id)) .. "  |cff888888(ID " .. entry.id .. ")|r",
           ItemIcon(entry.id)
  end
  return '"' .. entry.name .. '"  |cff888888(' .. L.NAME .. ")|r", QUESTION_ICON
end

-- Texte saisi -> entrée : lien d'objet ou nombre = itemID, sinon un nom.
local function ParseEntry(text)
  text = Trim(text)
  if text == "" then return nil end
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
  if id then return { id = id } end
  local linkName = text:match("|h%[(.-)%]|h")
  return { name = linkName or text }
end

local function SameEntry(a, b)
  if a.id or b.id then return a.id == b.id end
  return a.name:lower() == b.name:lower()
end

local function AddEntry(text)
  local entry = ParseEntry(text)
  if not entry then return end
  for _, existing in ipairs(DB().exclusions) do
    if SameEntry(existing, entry) then
      ns.Print(L.ALREADY_LISTED)
      return
    end
  end
  table.insert(DB().exclusions, entry)
  listOffset = math.max(0, #DB().exclusions - ROWS)
  frame.input:SetText("")
  RefreshList()
end

RefreshList = function()
  if not frame then return end
  local list = DB().exclusions
  local maxOffset = math.max(0, #list - ROWS)
  if listOffset > maxOffset then listOffset = maxOffset end

  for i, row in ipairs(frame.rows) do
    local index = listOffset + i
    local entry = list[index]
    if entry then
      local text, icon = EntryLabel(entry)
      row.text:SetText(text)
      row.icon:SetTexture(icon)
      row.entry, row.index = entry, index
      row:Show()
    else
      row.entry, row.index = nil, nil
      row:Hide()
    end
  end

  if #list == 0 then
    frame.counter:SetText(L.NO_EXCLUSION)
  else
    frame.counter:SetText(("%d-%d / %d%s"):format(listOffset + 1, math.min(listOffset + ROWS, #list), #list,
      #list > ROWS and ("  " .. L.SCROLL_HINT) or ""))
  end
end

local function CreateRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(WIDTH - 56, ROW_H)
  row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_H)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", 2, 0)

  row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.text:SetPoint("RIGHT", -30, 0)
  row.text:SetJustifyH("LEFT")

  row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.remove:SetSize(22, 18)
  row.remove:SetPoint("RIGHT", -2, 0)
  row.remove:SetText("X")
  row.remove:SetScript("OnClick", function()
    if row.index then
      table.remove(DB().exclusions, row.index)
      RefreshList()
    end
  end)

  row:SetScript("OnEnter", function(self)
    if self.entry and self.entry.id then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetItemByID, GameTooltip, self.entry.id)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

------------------------------------------------------------------------
-- Construction de la fenêtre
------------------------------------------------------------------------
local function CreateOptionsFrame()
  local ok, f = pcall(CreateFrame, "Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", FRAME_NAME, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
      })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  frame = f
  f.checks = {}

  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  table.insert(UISpecialFrames, FRAME_NAME) -- fermeture avec Échap

  local title = rawget(f, "TitleText")
  if type(title) ~= "table" then
    title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -6)
  end
  title:SetText(L.OPTIONS_TITLE)

  -- Affichage ------------------------------------------------------------
  local y = -34
  Header(f, L.SECTION_DISPLAY, y)
  Check(f, L.ONLY_AT_AH, 16, y - 18,
    function() return DB().onlyAtAH end,
    function(v) DB().onlyAtAH = v; ns.UpdateScanButtons() end,
    nil, L.ONLY_AT_AH_TIP)

  -- Rareté ---------------------------------------------------------------
  y = -88
  Header(f, L.SECTION_RARITY, y)
  for i, q in ipairs(ns.QUALITIES) do
    local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
    local r, g, b = QualityColor(q)
    Check(f, QualityName(q), 16 + col * 135, y - 18 - line * 24,
      function() return DB().qualities[q] ~= false end,
      function(v) DB().qualities[q] = v end,
      { r, g, b })
  end

  -- Scanner uniquement ---------------------------------------------------
  y = -164
  Header(f, L.SECTION_SCAN_ONLY, y)
  Hint(f, L.SCAN_ONLY_HINT, y - 16)
  local CAT_LABELS = {
    equipment = { L.CAT_EQUIPMENT, L.CAT_EQUIPMENT_TIP },
    crafting = { L.CAT_CRAFTING, L.CAT_CRAFTING_TIP },
    consumable = { L.CAT_CONSUMABLE, L.CAT_CONSUMABLE_TIP },
  }
  for i, key in ipairs(ns.CATEGORY_KEYS) do
    Check(f, CAT_LABELS[key][1], 16, y - 32 - (i - 1) * 24,
      function() return DB().categories[key] end,
      function(v) DB().categories[key] = v end,
      nil, CAT_LABELS[key][2])
  end

  -- Objets exclus --------------------------------------------------------
  y = -278
  Header(f, L.SECTION_EXCLUDE, y)
  Hint(f, L.EXCLUDE_HINT, y - 16)

  local input = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  input:SetSize(WIDTH - 140, 20)
  input:SetPoint("TOPLEFT", 24, y - 34)
  input:SetAutoFocus(false)
  input:SetScript("OnEnterPressed", function(self) AddEntry(self:GetText()) end)
  input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.input = input

  local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  add:SetSize(86, 22)
  add:SetPoint("LEFT", input, "RIGHT", 8, 0)
  add:SetText(L.ADD)
  add:SetScript("OnClick", function() AddEntry(input:GetText()) end)
  f.addButton = add

  local list = CreateFrame("Frame", nil, f)
  list:SetSize(WIDTH - 40, ROWS * ROW_H + 8)
  list:SetPoint("TOPLEFT", 20, y - 62)
  local bg = list:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    listOffset = math.max(0, listOffset - delta)
    RefreshList()
  end)
  f.list = list

  f.rows = {}
  for i = 1, ROWS do f.rows[i] = CreateRow(list, i) end

  f.counter = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  f.counter:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -6)

  f:SetScript("OnShow", function()
    for _, refresh in ipairs(refreshers) do refresh() end
    RefreshList()
  end)
end

------------------------------------------------------------------------
-- Maj+clic sur un objet pendant que la zone de saisie a le focus
------------------------------------------------------------------------
local function OnInsertLink(link)
  if frame and frame:IsShown() and frame.input:HasFocus() and type(link) == "string" then
    frame.input:SetText(link)
  end
end
if type(ChatEdit_InsertLink) == "function" then
  hooksecurefunc("ChatEdit_InsertLink", OnInsertLink)
end
if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
  hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
end

------------------------------------------------------------------------
-- API pour le reste de l'addon
------------------------------------------------------------------------
function ns.ToggleOptions()
  if not frame then CreateOptionsFrame() end
  frame:SetShown(not frame:IsShown())
end

function ns.RefreshOptions()
  if frame and frame:IsShown() then
    for _, refresh in ipairs(refreshers) do refresh() end
    RefreshList()
  end
end

function ns.OnItemInfoReceived()
  if frame and frame:IsShown() then RefreshList() end
end
