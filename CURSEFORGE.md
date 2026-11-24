# Baganator AH
 
**Check the auction house for everything in your bank or bags — on any of your characters — in one click.**
 
Baganator AH adds an **AH Scan** button to the [Baganator](https://www.curseforge.com/wow/addons/baganator) bank and bag windows. One click sends every distinct item shown in the window to [Auctionator](https://www.curseforge.com/wow/addons/auctionator) as a temporary shopping list, so you can see at a glance what is listed and at what price.
 
## How it works
 
* **Left-click** the **AH Scan** button above the bank or bag window: the items are searched on the auction house.
* **Right-click** the button: the options open.
* **Works with your alts.** Select another character in Baganator's character list and scan its bank or bags from its cached contents (Syndicator) — no need to log in on that character.
* **Auction house closed?** The search waits and starts automatically the next time you open the auction house.
* **Bound items are always skipped**, since they cannot be sold.
## Options
 
* **Display only when the auction house is open** — hides the buttons the rest of the time.
* **Filter by rarity** — one box per rarity, from Poor to Legendary (Poor is off by default).
* **Scan only** — equipment, crafting reagents and/or consumables. Only the checked categories are scanned; no box checked means every item.
* **Filter items** — a list of items you never want to scan. Type a name or an itemID, or Shift+click an item, then press Enter.
## Languages
 
English, French, German, Spanish (Spain and Mexico), Italian, Brazilian Portuguese, Russian, Korean, Simplified and Traditional Chinese.
 
## Requirements
 
* [Baganator](https://www.curseforge.com/wow/addons/baganator)
* [Syndicator](https://www.curseforge.com/wow/addons/syndicator) (installed with Baganator)
* [Auctionator](https://www.curseforge.com/wow/addons/auctionator)
Made for **WoW: Forever**.
 
## Commands
 
| Command | Effect |
|---|---|
| `/bah options` | Open the options |
| `/bah scan [bank\|bags] [Name-Realm]` | Scan the visible window, or a given character |
| `/bah quality <0-5>` | Scan from this rarity up (0 = Poor, 2 = Uncommon...) |
| `/bah who`, `/bah dump`, `/bah debug` | Diagnostics, useful when reporting a problem |
 
## FAQ
 
**The button does not appear.** Open the bank or bags once, then try `/bah attach`. If you checked "Display only when the auction house is open", the buttons only show at the auction house — use `/bah options` to change it.
 
**"Nothing to search".** The message tells you what was skipped (rarity, categories, excluded items, bound items). Right-click the button to check the filters.
 
**The wrong character is scanned.** Run `/bah who` with the alt displayed in Baganator and include the output in your bug report.
 
## Bug reports and suggestions
 
Please use the issue tracker and include the output of `/bah debug`.
 
*Baganator AH is an independent addon. It is not made by, endorsed by or affiliated with the authors of Baganator, Syndicator or Auctionator.*