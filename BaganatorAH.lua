local ADDON_NAME, ns = ...

------------------------------------------------------------------------
-- Constantes et utilitaires
------------------------------------------------------------------------
local CALLER_ID = "BaganatorAH"
local PREFIX = "|cff33ccffBaganator AH|r : "

local L = ns.L -- défini dans Locales.lua

-- Raretés gérées : 0 = médiocre (gris) ... 5 = légendaire.
ns.QUALITIES = { 0, 1, 2, 3, 4, 5 }
-- Catégories de "Scanner uniquement", dans l'ordre d'affichage.
ns.CATEGORY_KEYS = { "equipment", "crafting", "consumable" }

local DEFAULTS = {
  -- Raretés à scanner (false = ignorée). Gris ignoré par défaut.
  qualities = { [0] = false, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true },
  onlyAtAH = false,      -- boutons « Scan HV » visibles seulement quand l'HV est ouvert
  chatMessages = true,   -- messages courants dans le chat (les erreurs restent toujours affichées)
  exclusions = {},       -- objets exclus : { id = 1234 } ou { name = "Nom" }
  categories = { equipment = false, crafting = false, consumable = false },
  -- Position des boutons : point du bouton, point de la fenêtre, décalage x, y
  anchor = { "BOTTOMRIGHT", "TOPRIGHT", 0, 2 },
}

local function Print(fmt, ...)
  if select("#", ...) > 0 then
    local args = { ... }
    for i = 1, select("#", ...) do args[i] = tostring(args[i]) end
    fmt = fmt:format(unpack(args))
  end
  print(PREFIX .. fmt)
end
ns.Print = Print

-- Message courant (résumé du scan, avis...) : masqué si l'option est décochée.
-- Les erreurs et les réponses aux commandes /bah utilisent Print.
local function Log(...)
  if not BaganatorAHDB or BaganatorAHDB.chatMessages ~= false then Print(...) end
end
ns.Log = Log

-- Version lue dans le TOC (remplie à la publication). Depuis le dépôt git,
-- le TOC contient encore "@project-version@" : on affiche alors "dev".
local function ReadVersion()
  local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, version = false, nil
  if getMetadata then ok, version = pcall(getMetadata, ADDON_NAME, "Version") end
  if not ok or type(version) ~= "string" or version == "" or version:find("@", 1, true) then
    return "dev"
  end
  return version
end
ns.VERSION = ReadVersion()

-- Complète les réglages sauvegardés avec les valeurs par défaut manquantes.
local function Merge(dst, src)
  for key, value in pairs(src) do
    if dst[key] == nil then
      dst[key] = type(value) == "table" and CopyTable(value) or value
    elseif type(value) == "table" and type(dst[key]) == "table" and key ~= "exclusions" then
      Merge(dst[key], value)
    end
  end
end

local function InitDB()
  BaganatorAHDB = BaganatorAHDB or {}
  local db = BaganatorAHDB
  -- Ancien réglage (v0.1 à v0.4) : qualité minimale -> cases de rareté.
  if db.qualities == nil and type(db.minQuality) == "number" then
    db.qualities = {}
    for _, q in ipairs(ns.QUALITIES) do db.qualities[q] = q >= db.minQuality end
  end
  db.minQuality = nil
  -- Réglages retirés : icône de la minimap (v0.5), objets liés et mode ET/OU (v0.6).
  db.minimap, db.includeBound, db.categoryMode = nil, nil, nil
  Merge(db, DEFAULTS)
end

local function AuctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

local function SyndicatorAPI()
  return Syndicator and Syndicator.API
end

------------------------------------------------------------------------
-- Les deux types de contenu : "bank" (banque) et "bags" (sacs)
------------------------------------------------------------------------
-- Dans les données Syndicator d'un personnage, quelle clé correspond à quoi ?
local function KeyMatchesKind(kind, key)
  local k = key:lower()
  if k:find("guild", 1, true) then return false end
  if kind == "bank" then
    return k:find("bank", 1, true) ~= nil
  elseif kind == "bags" then
    return k:find("bag", 1, true) ~= nil and k:find("bank", 1, true) == nil
  end
  return false
end

-- Une fenêtre (ou un nom de région) Baganator est-elle la banque ou les sacs ?
local function FrameKind(text)
  text = tostring(text or ""):lower()
  if text:find("guild", 1, true) then return nil end
  if text:find("bank", 1, true) then return "bank" end
  if text:find("backpack", 1, true) then return "bags" end
end

-- Texte traduit propre au type : KindText("RESULT", "bags") -> L.RESULT_BAGS
local function KindText(prefix, kind)
  return L[prefix .. (kind == "bags" and "_BAGS" or "_BANK")]
end

------------------------------------------------------------------------
-- Lecture des données via Syndicator (le cache utilisé par Baganator)
------------------------------------------------------------------------
local function CurrentCharacter()
  local api = SyndicatorAPI()
  if api and api.GetCurrentCharacter then
    return api.GetCurrentCharacter()
  end
end

-- Un nom est un personnage valide s'il a des données dans Syndicator.
local function IsKnownCharacter(name)
  local api = SyndicatorAPI()
  if not (api and api.GetCharacter) or type(name) ~= "string" or name == "" then return false end
  local ok, data = pcall(api.GetCharacter, name)
  return ok and type(data) == "table"
end

-- Priorité des champs qui peuvent contenir le personnage affiché par Baganator.
local function KeyScore(lowerKey)
  if lowerKey:find("live", 1, true) then return 0 end       -- "liveCharacter" = personnage connecté
  if lowerKey == "lastcharacter" then return 4 end
  if lowerKey:find("current", 1, true) then return 1 end
  if lowerKey:find("character", 1, true) then return 3 end
  if lowerKey:find("char", 1, true) then return 2 end
  return 0
end

local SKIP_KEYS = { parent = true, Parent = true, owner = true, Owner = true }

local function IsObject(value)
  return type(value) == "table" and value.GetObjectType ~= nil
end

-- Baganator range le personnage affiché dans un sous-objet de la fenêtre
-- (par ex. frame.Character.lastCharacter), pas sur la fenêtre elle-même.
-- On parcourt donc la fenêtre et ses sous-objets VISIBLES, jusqu'à 3 niveaux,
-- et on retient le champ "personnage" qui désigne un personnage connu de
-- Syndicator. Retourne : nom, chemin du champ, liste des candidats, et un
-- booléen indiquant qu'une sous-vue "Live" (personnage connecté) est visible.
local function FindDisplayedCharacter(root)
  local best, bestPath, bestRank
  local candidates, visited, budget = {}, {}, 300
  local liveShown = false

  local function walk(obj, path, depth)
    if visited[obj] or budget <= 0 or obj == UIParent then return end
    visited[obj] = true
    budget = budget - 1

    for key, value in pairs(obj) do
      if type(key) == "string" and not SKIP_KEYS[key] then
        if type(value) == "string" then
          local score = KeyScore(key:lower())
          if score > 0 and IsKnownCharacter(value) then
            local fieldPath = path .. "." .. key
            candidates[#candidates + 1] = fieldPath .. " = " .. value
            local rank = score * 10 - depth
            if not bestRank or rank > bestRank then
              best, bestPath, bestRank = value, fieldPath, rank
            end
          end
        elseif depth < 3 and IsObject(value) and (not value.IsShown or value:IsShown()) then
          if key:lower():find("live", 1, true) then liveShown = true end
          walk(value, path .. "." .. key, depth + 1)
        end
      end
    end
  end

  if root then
    walk(root, root.GetName and root:GetName() or "frame", 0)
  end
  return best, bestPath, candidates, liveShown
end

-- Retourne le personnage affiché dans la fenêtre Baganator, et un booléen
-- indiquant si on l'a réellement détecté (sinon : personnage connecté).
local function DisplayedCharacter(frame)
  local found, _, _, liveShown = FindDisplayedCharacter(frame)
  if found then return found, true end
  if liveShown then return CurrentCharacter(), true end -- vue du personnage connecté
  return CurrentCharacter(), false
end

-- Parcours récursif : on ne présume pas de la forme exacte des données de
-- Syndicator. Toute table ayant un itemID ou un itemLink est un objet, et
-- toute chaîne contenant "item:" est traitée comme un lien d'objet.
local function CollectItems(node, out, depth)
  local kind = type(node)
  if kind == "string" then
    if node:find("item:", 1, true) then
      out[#out + 1] = { itemLink = node, itemID = tonumber(node:match("item:(%d+)")) }
    end
    return
  end
  if kind ~= "table" or depth > 6 then return end
  if node.itemID or node.itemLink then
    out[#out + 1] = node
    return
  end
  for _, child in pairs(node) do
    CollectItems(child, out, depth + 1)
  end
end

-- Toutes les clés du personnage qui correspondent à la banque ou aux sacs.
local function CollectKind(data, kind, out)
  local foundKey = false
  for key, value in pairs(data) do
    if type(key) == "string" and KeyMatchesKind(kind, key) then
      foundKey = true
      CollectItems(value, out, 0)
    end
  end
  return foundKey
end

local function ItemName(slot, itemID)
  if type(slot.itemLink) == "string" then
    local name = slot.itemLink:match("|h%[(.-)%]|h")
    if name and name ~= "" then return name end
  end
  if itemID and C_Item and C_Item.GetItemNameByID then
    return C_Item.GetItemNameByID(itemID)
  end
end

local function SlotQuality(slot, itemID)
  if slot.quality then return slot.quality end
  if itemID and C_Item and C_Item.GetItemQualityByID then
    local ok, quality = pcall(C_Item.GetItemQualityByID, itemID)
    if ok then return quality end
  end
end

------------------------------------------------------------------------
-- Filtres : catégories (équipement / artisanat / consommables)
------------------------------------------------------------------------
-- Classes d'objets du jeu (Enum.ItemClass) : 0 consommable, 2 arme,
-- 3 gemme, 4 armure, 5 composant, 7 artisanat (tissu, minerai, herbes...).
local function ItemClassID(itemID)
  if not itemID then return nil end
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not getInstant then return nil end
  local ok, _, _, _, _, _, classID = pcall(getInstant, itemID)
  if ok then return classID end
end

local function IsCraftingReagent(itemID)
  local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not getInfo then return false end
  local ok, flag = pcall(function() return select(17, getInfo(itemID)) end)
  return ok and flag == true
end

local function ItemCategories(itemID)
  local classID = ItemClassID(itemID)
  if classID == nil then return nil end
  local cats = {
    equipment = classID == 2 or classID == 4,
    crafting = classID == 3 or classID == 5 or classID == 7,
    consumable = classID == 0,
  }
  if not cats.crafting and IsCraftingReagent(itemID) then cats.crafting = true end
  return cats
end
ns.ItemCategories = ItemCategories

-- Aucune catégorie cochée = tout passe. Sinon l'objet doit appartenir à
-- l'une des catégories cochées.
local function PassesCategory(itemID)
  local db = BaganatorAHDB
  local active = {}
  for _, key in ipairs(ns.CATEGORY_KEYS) do
    if db.categories[key] then active[#active + 1] = key end
  end
  if #active == 0 then return true end

  local cats = ItemCategories(itemID)
  if not cats then return false end
  for _, key in ipairs(active) do
    if cats[key] then return true end
  end
  return false
end

-- Liste d'exclusion, préparée une fois par scan.
local function BuildExclusions()
  local ids, names = {}, {}
  for _, entry in ipairs(BaganatorAHDB.exclusions) do
    if entry.id then ids[entry.id] = true end
    if entry.name then names[entry.name:lower()] = true end
  end
  return ids, names
end

local function AddName(g, name)
  if g.exNames[name:lower()] then
    g.stats.excluded = g.stats.excluded + 1
  elseif not g.names[name] then
    g.names[name] = true
    g.order[#g.order + 1] = name
  end
end

-- Lit la banque ou les sacs d'un personnage. Retourne une table :
--   order      = noms d'objets distincts déjà connus
--   unresolved = itemID dont le nom n'est pas encore en cache
--   stats      = compteurs pour le diagnostic
local function Gather(character, kind)
  local api = SyndicatorAPI()
  if not (api and api.GetCharacter) then return nil, "nosyndicator" end

  local data = api.GetCharacter(character)
  if type(data) ~= "table" then return nil, "nodata" end

  local slots = {}
  if not CollectKind(data, kind, slots) then return nil, "nodata" end

  local db = BaganatorAHDB
  local exIDs, exNames = BuildExclusions()
  local g = {
    names = {}, order = {}, unresolved = {}, exNames = exNames,
    stats = { items = #slots, bound = 0, quality = 0, excluded = 0, category = 0, noname = 0 },
  }
  local stats, unresolvedSet = g.stats, {}

  for _, slot in ipairs(slots) do
    local itemID = slot.itemID
    if not itemID and type(slot.itemLink) == "string" then
      itemID = tonumber(slot.itemLink:match("item:(%d+)"))
    end
    local quality = SlotQuality(slot, itemID)

    if slot.isBound then -- un objet lié ne peut pas être vendu à l'HV
      stats.bound = stats.bound + 1
    elseif quality and db.qualities[quality] == false then
      stats.quality = stats.quality + 1
    elseif itemID and exIDs[itemID] then
      stats.excluded = stats.excluded + 1
    elseif not PassesCategory(itemID) then
      stats.category = stats.category + 1
    else
      local name = ItemName(slot, itemID)
      if name then
        AddName(g, name)
      elseif itemID then
        if not unresolvedSet[itemID] then
          unresolvedSet[itemID] = true
          g.unresolved[#g.unresolved + 1] = itemID
        end
      else
        stats.noname = stats.noname + 1
      end
    end
  end

  return g
end

-- " (skipped: 3 bound, 2 excluded)" traduit ; vide si rien n'a été ignoré.
local function SkipSummary(s)
  local parts = {}
  local function add(n, key)
    if n > 0 then parts[#parts + 1] = L[key]:format(n) end
  end
  add(s.bound, "SKIP_BOUND")
  add(s.quality, "SKIP_RARITY")
  add(s.excluded, "SKIP_EXCLUDED")
  add(s.category, "SKIP_CATEGORY")
  add(s.noname, "SKIP_UNNAMED")
  if #parts == 0 then return "" end
  return L.SKIPPED:format(table.concat(parts, ", "))
end

-- Demande au jeu le nom des objets pas encore en cache, puis appelle done().
local function ResolveNames(g, done)
  if #g.unresolved == 0 or not Item or not Item.CreateFromItemID then
    g.stats.noname = g.stats.noname + #g.unresolved
    done()
    return
  end

  local finished = false
  local remaining = #g.unresolved
  local function finish()
    if finished then return end
    finished = true
    -- Objets dont le nom n'est jamais arrivé avant le délai.
    if remaining > 0 then g.stats.noname = g.stats.noname + remaining end
    done()
  end

  local function settle(name)
    if finished then return end
    if name then
      AddName(g, name)
    else
      g.stats.noname = g.stats.noname + 1
    end
    remaining = remaining - 1
    if remaining <= 0 then finish() end
  end

  for _, itemID in ipairs(g.unresolved) do
    -- Un objet inexistant ou supprimé peut faire lever une erreur au jeu :
    -- on l'ignore au lieu d'interrompre tout le scan.
    local ok = pcall(function()
      local item = Item:CreateFromItemID(itemID)
      item:ContinueOnItemLoad(function() settle(item:GetItemName()) end)
    end)
    if not ok then settle(nil) end
  end
  if not finished then
    C_Timer.After(4, finish) -- on n'attend pas indéfiniment
  end
end

------------------------------------------------------------------------
-- Envoi vers Auctionator (liste temporaire via son API publique)
------------------------------------------------------------------------
local pendingTerms

local function RunSearch(terms)
  local v1 = AuctionatorAPI()
  if not v1 then
    Print(L.AUCTIONATOR_MISSING)
    return
  end

  local ok, err
  if v1.MultiSearchExact then
    ok, err = pcall(v1.MultiSearchExact, CALLER_ID, terms)
  elseif v1.MultiSearch then
    -- Anciennes versions : on met nous-mêmes les noms entre guillemets
    -- (syntaxe de recherche exacte d'Auctionator).
    local quoted = {}
    for i, name in ipairs(terms) do quoted[i] = '"' .. name .. '"' end
    ok, err = pcall(v1.MultiSearch, CALLER_ID, quoted)
  else
    Print(L.AUCTIONATOR_NO_SEARCH)
    return
  end

  if not ok then
    Print(L.AUCTIONATOR_ERROR, err)
  end
end

local function Dispatch(terms)
  if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    pendingTerms = nil
    RunSearch(terms)
  else
    pendingTerms = terms
    Log(L.AH_CLOSED)
  end
end

local function FlushPending()
  if pendingTerms and AuctionHouseFrame and AuctionHouseFrame:IsShown() then
    local terms = pendingTerms
    pendingTerms = nil
    RunSearch(terms)
  end
end

local function Scan(character, kind)
  kind = kind or "bank"
  character = character or CurrentCharacter()
  if not character then
    Print(L.NO_CHARACTER)
    return
  end

  local g = Gather(character, kind)
  if not g then
    Print(KindText("NO_DATA", kind), character)
    return
  end

  ResolveNames(g, function()
    local terms = g.order
    table.sort(terms)
    local s = g.stats

    if #terms == 0 then
      Log(KindText("NOTHING", kind), character, s.items, SkipSummary(s))
      return
    end

    Log(KindText("RESULT", kind), character, #terms, SkipSummary(s))
    Dispatch(terms)
  end)
end

------------------------------------------------------------------------
-- Boutons sur les fenêtres de banque et de sacs de Baganator
------------------------------------------------------------------------
local buttons = {}     -- fenêtre -> bouton
local frameKinds = {}  -- fenêtre -> "bank" | "bags"
local ahOpen = false   -- mis à jour par AUCTION_HOUSE_SHOW / _CLOSED

local function UpdateScanButtons()
  local show = not BaganatorAHDB.onlyAtAH or ahOpen
  for _, button in pairs(buttons) do
    button:SetShown(show)
  end
end
ns.UpdateScanButtons = UpdateScanButtons

local function ShowTooltip(button, frame)
  local kind = frameKinds[frame] or "bank"
  local character, detected = DisplayedCharacter(frame)
  GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
  GameTooltip:SetText("Baganator AH |cff888888" .. ns.VERSION .. "|r")
  GameTooltip:AddLine(KindText("TOOLTIP", kind), 1, 1, 1, true)
  if character then
    local g = Gather(character, kind)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.CHARACTER, character, 0.7, 0.7, 0.7, 1, 1, 1)
    if not detected then
      GameTooltip:AddLine(L.NOT_DETECTED_SHORT, 1, 0.4, 0.4)
    end
    if g then
      GameTooltip:AddDoubleLine(L.DISTINCT_ITEMS, #g.order + #g.unresolved, 0.7, 0.7, 0.7, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.TOOLTIP_LEFT, 0, 1, 0)
  GameTooltip:AddLine(L.TOOLTIP_RIGHT, 0, 1, 0)
  GameTooltip:Show()
end

local function AttachTo(frame, kind)
  if not frame or buttons[frame] then return end

  local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  button:SetText(L.SCAN_BUTTON)
  -- Largeur adaptée au texte traduit (80 px minimum).
  local fontString = button.GetFontString and button:GetFontString()
  local textWidth = fontString and fontString.GetStringWidth and fontString:GetStringWidth() or 0
  button:SetSize(math.max(80, math.ceil(textWidth) + 24), 22)
  button:SetFrameLevel(frame:GetFrameLevel() + 10)
  local a = BaganatorAHDB.anchor
  button:SetPoint(a[1], frame, a[2], a[3], a[4])
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      GameTooltip:Hide()
      if ns.ToggleOptions then ns.ToggleOptions() end
      return
    end
    local character, detected = DisplayedCharacter(frame)
    if not detected then
      Log(L.NOT_DETECTED)
    end
    Scan(character, kind)
  end)
  button:SetScript("OnEnter", function(self) ShowTooltip(self, frame) end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  buttons[frame] = button
  frameKinds[frame] = kind
  button:SetShown(not BaganatorAHDB.onlyAtAH or ahOpen)
end

-- Repli : on cherche les fenêtres principales de Baganator dont le nom
-- contient "Bank" ou "Backpack" (leurs noms exacts varient selon la vue).
local function FindFrames()
  local found = {}
  for name, obj in pairs(_G) do
    if type(name) == "string" and name:find("^Baganator") and not name:find("Button") then
      local kind = FrameKind(name)
      if kind and type(obj) == "table" and obj.GetObjectType
         and obj:GetObjectType() == "Frame" and obj:GetParent() == UIParent then
        found[#found + 1] = { frame = obj, kind = kind }
      end
    end
  end
  return found
end

local function AttachToAllFrames()
  for _, entry in ipairs(FindFrames()) do
    AttachTo(entry.frame, entry.kind)
  end
end

-- Voie "officielle" : l'API de skins de Baganator signale chaque fenêtre.
local function RegisterSkinListener()
  local skins = Baganator and Baganator.API and Baganator.API.Skins
  if not (skins and skins.RegisterListener) then return end

  pcall(skins.RegisterListener, function(details)
    if type(details) ~= "table" or details.regionType ~= "ButtonFrame" then return end
    local region = details.region
    if not region then return end

    local name = region.GetName and region:GetName() or ""
    local tagText = ""
    if type(details.tags) == "table" then
      for key, value in pairs(details.tags) do
        tagText = tagText .. " " .. tostring(key) .. " " .. tostring(value)
      end
    end
    local kind = FrameKind(name) or FrameKind(tagText)
    if kind then AttachTo(region, kind) end
  end)
end

------------------------------------------------------------------------
-- Diagnostic
------------------------------------------------------------------------
local function ListFunctions(tbl)
  local names = {}
  for key, value in pairs(tbl or {}) do
    if type(value) == "function" then names[#names + 1] = tostring(key) end
  end
  table.sort(names)
  return #names > 0 and table.concat(names, ", ") or "-"
end

local function Truncate(text, max)
  text = tostring(text)
  if #text > max then return text:sub(1, max) .. "..." end
  return text
end

-- Affiche l'arborescence des données (2 enfants non vides par niveau) pour
-- voir à quoi ressemblent réellement les objets.
local function DumpNode(node, path, depth, budget)
  if budget.n <= 0 then return end
  budget.n = budget.n - 1

  if type(node) ~= "table" then
    Print("  %s = %s", path, Truncate(node, 120))
    return
  end

  local keys, allLeaves = {}, true
  for key, value in pairs(node) do
    keys[#keys + 1] = key
    if type(value) == "table" then allLeaves = false end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  if allLeaves then
    local parts = {}
    for _, key in ipairs(keys) do
      parts[#parts + 1] = tostring(key) .. "=" .. Truncate(node[key], 40)
    end
    Print("  %s = { %s }", path, Truncate(table.concat(parts, ", "), 220))
    return
  end

  Print("  %s: table (%d entries)", path, #keys)
  if depth >= 4 then return end

  local shown = 0
  for _, key in ipairs(keys) do
    local value = node[key]
    if not (type(value) == "table" and next(value) == nil) then
      DumpNode(value, path .. "." .. tostring(key), depth + 1, budget)
      shown = shown + 1
      if shown >= 2 then break end
    end
  end
end

local function Dump(character, kind)
  kind = kind or "bank"
  character = character or CurrentCharacter()
  Print("Character: %s (%s)", character, kind)

  local api = SyndicatorAPI()
  local data = api and api.GetCharacter and api.GetCharacter(character)
  if type(data) ~= "table" then
    Print("Syndicator returns no data for this character.")
    return
  end

  Print("Character data contents:")
  local keys = {}
  for key in pairs(data) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do
    local value = data[key]
    if type(value) == "table" then
      local list = {}
      CollectItems(value, list, 0)
      Print("  %s: table, %d items detected", key, #list)
    else
      Print("  %s: %s", key, type(value))
    end
  end

  for _, key in ipairs(keys) do
    if type(key) == "string" and KeyMatchesKind(kind, key) and type(data[key]) == "table" then
      Print("Sample of '%s':", key)
      DumpNode(data[key], key, 0, { n = 25 })
    end
  end
end

local function Who()
  Print("Logged-in character: %s", tostring(CurrentCharacter()))
  local n = 0
  for frame, kind in pairs(frameKinds) do
    n = n + 1
    local found, path, candidates, liveShown = FindDisplayedCharacter(frame)
    Print("Frame: %s [%s] (%s)", tostring(frame:GetName()), kind,
          frame:IsVisible() and "visible" or "hidden")
    Print("  Detected: %s via %s", tostring(found), tostring(path))
    Print("  'Live' view shown: %s", tostring(liveShown))
    for _, c in ipairs(candidates) do Print("  candidate: " .. c) end

    local children = {}
    for key, value in pairs(frame) do
      if type(key) == "string" and IsObject(value) and not SKIP_KEYS[key] then
        children[#children + 1] = key .. (value.IsShown and value:IsShown() and "*" or "")
        if value.IsShown and value:IsShown() then
          for key2, value2 in pairs(value) do
            if type(key2) == "string" and IsObject(value2) and not SKIP_KEYS[key2] then
              children[#children + 1] = key .. "." .. key2 .. (value2.IsShown and value2:IsShown() and "*" or "")
            end
          end
        end
      end
    end
    table.sort(children)
    Print("  Sub-objects (* = shown): %s",
          Truncate(table.concat(children, ", "), 400))
  end
  if n == 0 then
    Print("No Baganator window detected (/bah attach).")
  end
end

local function Debug()
  Print("Syndicator.API: " .. ListFunctions(SyndicatorAPI()))
  Print("Auctionator.API.v1: " .. ListFunctions(AuctionatorAPI()))
  Print("Baganator.API.Skins: " .. ListFunctions(Baganator and Baganator.API and Baganator.API.Skins))
  Print("Current character: " .. tostring(CurrentCharacter()))
  local n = 0
  for frame, kind in pairs(frameKinds) do
    n = n + 1
    Print("Frame: %s [%s]", tostring(frame:GetName()), kind)
  end
  if n == 0 then
    Print("No Baganator window detected.")
    local names = {}
    for name in pairs(_G) do
      if type(name) == "string" and name:find("^Baganator") and FrameKind(name) then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    Print("Globals: " .. (#names > 0 and table.concat(names, ", ") or "-"))
  end
end

------------------------------------------------------------------------
-- Commandes /bah
------------------------------------------------------------------------
local function Help()
  Print(L.HELP_TITLE)
  print("  /bah scan [bank|bags] [Name-Realm] - " .. L.HELP_SCAN)
  print("  /bah options - " .. L.HELP_OPTIONS)
  print("  /bah quality <0-5> - " .. L.HELP_QUALITY)
  print("  /bah attach - " .. L.HELP_ATTACH)
  print("  /bah who - " .. L.HELP_WHO)
  print("  /bah dump [bank|bags] [Name-Realm] - " .. L.HELP_DUMP)
  print("  /bah debug - " .. L.HELP_DEBUG)
end

local KIND_WORDS = {
  bank = "bank", banque = "bank",
  bags = "bags", bag = "bags", sacs = "bags", sac = "bags",
}

-- "bags Eva Zionfiscale-PvE" -> "bags", "Eva Zionfiscale-PvE"
local function ParseArgs(rest)
  local first, remainder = rest:match("^(%S+)%s*(.*)$")
  if first and KIND_WORDS[first:lower()] then
    return KIND_WORDS[first:lower()], remainder ~= "" and remainder or nil
  end
  return nil, rest ~= "" and rest or nil
end

-- Sans argument : on vise la fenêtre visible (banque d'abord, puis sacs).
local function VisibleTarget(kind)
  local order = kind and { kind } or { "bank", "bags" }
  for _, wanted in ipairs(order) do
    for frame, frameKind in pairs(frameKinds) do
      if frameKind == wanted and frame:IsVisible() then
        return (DisplayedCharacter(frame)), wanted
      end
    end
  end
  return nil, kind
end

SLASH_BAGANATORAH1 = "/bah"
SLASH_BAGANATORAH2 = "/baganatorah"
SlashCmdList["BAGANATORAH"] = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()

  if cmd == "" or cmd == "scan" then
    local kind, name = ParseArgs(rest)
    if name then
      Scan(name, kind or "bank")
    else
      local character, targetKind = VisibleTarget(kind)
      Scan(character, targetKind or "bank")
    end
  elseif cmd == "dump" then
    local kind, name = ParseArgs(rest)
    if name then
      Dump(name, kind)
    else
      local character, targetKind = VisibleTarget(kind)
      Dump(character, targetKind)
    end
  elseif cmd == "who" then
    Who()
  elseif cmd == "options" or cmd == "config" or cmd == "opt" then
    if ns.ToggleOptions then ns.ToggleOptions() end
  elseif cmd == "quality" then
    local q = tonumber(rest)
    if q then
      for _, quality in ipairs(ns.QUALITIES) do
        BaganatorAHDB.qualities[quality] = quality >= q
      end
      if ns.RefreshOptions then ns.RefreshOptions() end
      Print(L.MIN_RARITY, q)
    else
      Help()
    end
  elseif cmd == "attach" then
    AttachToAllFrames()
    Print(L.WINDOWS_DETECTED, #FindFrames())
  elseif cmd == "debug" then
    Debug()
  else
    Help()
  end
end

------------------------------------------------------------------------
-- Événements
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
-- Ces événements peuvent ne pas exister selon le client : on protège.
pcall(events.RegisterEvent, events, "BANKFRAME_OPENED")
pcall(events.RegisterEvent, events, "AUCTION_HOUSE_SHOW")
pcall(events.RegisterEvent, events, "AUCTION_HOUSE_CLOSED")
pcall(events.RegisterEvent, events, "GET_ITEM_INFO_RECEIVED")

events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON_NAME then InitDB() end

  elseif event == "PLAYER_LOGIN" then
    ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false
    RegisterSkinListener()
    for _, delay in ipairs({ 1, 3, 8 }) do
      C_Timer.After(delay, AttachToAllFrames)
    end

  elseif event == "BANKFRAME_OPENED" then
    C_Timer.After(0.2, AttachToAllFrames)
    C_Timer.After(1.5, AttachToAllFrames)

  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    AttachToAllFrames()
    UpdateScanButtons()
    C_Timer.After(0.5, FlushPending)

  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
    UpdateScanButtons()

  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if ns.OnItemInfoReceived then ns.OnItemInfoReceived() end
  end
end)
