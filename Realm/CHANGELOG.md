# Realm changelog

## 4.10.1
- Buttons: the Exchange ">" and POST list buttons on the auction house now sit side by side at the bottom right, in a flat dark style with a thin border and a blue hover instead of the red template art (new shared `UI.Modern` style; the other buttons follow in a later version).
- Bags: the Alts button works again (it sat under the new double-click-to-fold area); the header now double-clicks to fold into the pouch. The character name is large in their class colour, the gold line is bigger with an outline, and the top-right corner has a flat close button and evenly spaced icons.
- New: Send list. Items Realm holds back (gear you can use, profession goods, quest items) are listed and you choose which may be mailed to your AH alt. Open it from the bag header or the EMF mail window (both show the same list), click a row to allow or remove an item, or turn on Add by click or Remove by click and click items in your bags. Realm asks once about each newly held-back item when you open a mailbox. `/realm mule ok|unok <item>` and `/realm mule list` do the same.
- Mule: the AH alt is confirmed by logging in on it once, with an optional test letter as extra proof; the keep rules never mail gear or materials your class and professions can use; a game error while mailing no longer causes a Lua error.
- Replay: open-world PvP only (battlegrounds are no longer recorded); a 1v1 that grows into a bigger fight stays one recording.
- Fix: the party buff and heal scanners no longer error on the "secret" in-range answer some clients return.

## 4.10.0
- Fix: the compass no longer sends you to accept a quest the giver cannot offer yet. Each route accept step now waits until its real prerequisite quests are handed in (new Path\Prereqs.lua, built from Questie's quest data: "any of" and "all of" rules). A quest the giver actually lists always opens. Quests missing from the data fall back to the old same-spot rule.
- Fix: the compass no longer sends you to hand in a quest the game says is not ready, and it skips an "Accept quest" step when the giver has nothing to offer.
- Compass: quest step text shows as one line and expands on click; profession skill levels have a large line of their own; the Level Profession step tracks each profession being leveled; the compass returns to the quest route as soon as a new home inn is confirmed, including after /reload; trainer visits wait for a new skill level.
- New: class leveling buff alerts and heal bar with click settings for self and party.
- Bags and Mail: Drop and Delete changes, coin display, EMF stats, Exchange opens with the auction house.

## 4.9.2
- New look for the one bag window: dark navy, slightly see-through panel with a thin red-brown border; small yellow "Realm Bags" title; small white character line under it; the gold line on its own row in a larger, plain white font (coloured g, s and c letters); category headers in yellow with a thin red divider across the full width; a thinner yellow grabber bar in the footer; and a dark search box with a red-brown border at the lower right. Bag behaviour, Drop and the Delete button are unchanged.

## 4.9.1
- Fix: the bag Drop button now works when you loot with full bags. It also reacts when the full-bag message arrives slightly before the loot window opens or just after it closes, accepts the wording variants of that message, and if auto-loot leaves items behind with no free slot it drops without waiting for the message. If the loot window had already closed it tells you to loot again. A failed delete puts the item back. `/realm bags drop debug on|off` prints why a drop did or did not happen.
- New Drop button in the bag footer (next to Clean up). When it is on and a loot will not fit because your bags are full, the cheapest item in your bags is dropped (destroyed) and the loot is tried again, up to 3 times per loot window. Quest items, items with no vendor price, and rare or better items are never dropped. It is off by default. `/realm bags drop on|off` does the same. The search box is 8 pixels narrower to make room.
- Party members who run Realm now share gathering finds (herbs, ore, fishing spots, chests) over the tracker channel. A node you find for the first time is sent to your party, and finds from others are saved to your node list and drawn on the tracker map. A spot you already have is ignored. It needs `/realm track on`, and `/realm sharenodes on|off` turns sending and receiving off. Members on an older Realm are not affected. There is no catch-up for members who join late.
- Party tracker map now mirrors the compass: walking footprints run from your dot to your compass target, using the same icons and colours.
- Your compass goal is shared with party members who run Realm (accepting or handing in a quest, training, an inn, a dungeon, and the travel mode: tram, boat, zeppelin, flight path, walking, flying). Their map shows a marker where each member is heading with footprints from their dot, and the member list says what they are doing. Only the kind of goal, the NPC or place name and the position are sent, never quest titles. `/realm share on|off` turns it off. Members on an older Realm just show as a dot.
- Macros are now placed on main bar page 1 (solo) and page 2 (party) only, and only the rotation macros: empty buttons stay yours. Spare-spell filling is off by default (`/realm macros fill on`). `/realm macros pages 3|4|5` also places battlegrounds, small dungeon and raid. Buttons an earlier version filled beyond that are cleared. Macros for all five pages are still created so you can drag them from `/macro`.

## 4.9.0
- Macros now live on the main action bar pages: page 1 solo, page 2 party, page 3 battlegrounds, page 4 small dungeon groups, page 5 raids. Scroll the main bar to change page. Macros sit left to right in rotation order, and spare buttons on each page get other useful spells. Identical macros on several pages are one shared macro, so a full set stays inside your 30 macro slots. Keep the Right, Right 2 and Bottom Right bars switched off in Options > Action Bars, because pages 3 to 5 use the same buttons.
- Macros still follow your new spells, talents and level ups (`/realm macros autoupdate on|off`). A button that already holds something of yours is skipped unless you agreed in setup or run `/realm macros take`.
- New first-run setup window (`/realm setup` opens it again): auto-macros, macro autoupdate, the Leveler, flight master detours, auto-sell and repair, one bag, and the mail helper. Nothing changes until you press Apply.
- New one bag (`/realm bags`, `on`, `off`, `sort bag|type|quality|name|value`): search, sorting, a tab for every character you have played, and an All tab. Each character's bags (and bank, once opened) are saved when they change and at logout, so any alt can be viewed from any character. Saved views are look-only.
- New mail helper, EMF (`/realm mail`, or the Mail button on the Exchange window): collects money and items, deletes a mail only after the game confirms it is empty, never pays COD, and never deletes a letter a player wrote. It keeps a running tally of auction sales, items won, outbid refunds and returned items.
- The compass now draws a picture for the travel mode instead of `>>`: a train for the tram, a boat, an airship for the zeppelin, a bird for a flight master, and a rider on a bird when you are flying yourself.

## 4.8.4
- New option: detour to flight masters you have not opened yet (off by default). Turn it on in the compass menu ("Detour to new flight masters") or with `/path flights on`. While on, if you stand in a town whose flight master Realm has not seen you open, the compass points at the town and says "Find the flight master in <town>". It is not counted as a travel step. Open the flight master's map once and it carries on. `/path flights skip` drops it for that town until you /reload, and `/path flights off` turns the option off.
- The compass points at the town, not the flight master's exact spot, because Realm has no exact flight master coordinates.

## 4.8.3
- Data: macro spell lists for all 27 specs were checked against the Wowhead WoW: Forever rotation and cooldown guide of each spec (read 2026-11-07). MacroDataVersion is now 2, so installed macros refresh for autoupdate users.
  - Removed spells the Forever guides do not use in the rotation slots: Crusader Strike, Kill Command, Envenom, Devastate, Vampiric Touch, Mind Sear, Shadowfiend, Dispersion, Seed of Corruption, Shadowfury, Starfall, Earth Shield, and Death Wish from Arms.
  - Added spells the guides list: Slam, Rend, Victory Rush and Spearing Strike (Arms), Holy Strike (Paladin), Summon Hawk and Tranquilizing Shot (Hunter), Wrack (Affliction), Garrote and Rupture (Subtlety), Penance and Heal (Priest), Riptide (Restoration Shaman), Lightning Mastery, Rage of the Farseer, and others.
  - Not confirmed: WoWDB had no readable Forever data, so only Wowhead was used. The Assassination Rogue guide names its builder spell only by id, so the old builder is kept. Defensive, crowd control and utility slots are not covered by the guides and still come from the Realm class guides.
- Fix: the optional main-bar spell list in the macro data (`main`) is now actually used when filling the main bar.
- Tested: mock tests cover all 27 specs (255-character limit, 28 macro cap, every hotbar filled, main bar) and `/realm macros autoupdate on|off` in both states, including a rebuild queued during combat.

## 4.8.0
- New: macro module for WoW Forever. `/realm macros` builds real macros for your class and current spec and puts them on the bars:
  - Hotbar 1 solo and leveling, Hotbar 2 party, Hotbar 3 battlegrounds, Hotbar 4 raid, main bar other useful spells.
  - All 9 classes and all 27 specs. Up to 7 macros per hotbar (28 in total, inside the 30 character macro slots).
  - Out of combat only; changes made during combat wait until combat ends.
  - Macros you edited yourself are never overwritten (`/realm macros force` replaces them). Slots you filled yourself are never taken.
  - `/realm macros status | show [spec] | spec <name> | force | remove`.
- New: autoupdate toggle, saved per character, default ON. `/realm macros autoupdate on|off`, or the Macros section on the TheBoys settings page. When ON, learning a spell, a talent or spec change, or a level up rebuilds the macros with your newest spells (highest rank is automatic; replacement spells such as Demon Armor over Demon Skin are preferred). When OFF, macros stay exactly as they are until you run `/realm macros`. It only updates macros that were already installed.
- Data: spell lists come from the Realm class guides. Frost Mage was checked against Wowhead's WoW: Forever rotation guide (2026/11/02). The other 26 specs still need that check.

## 4.7.3
- New: travel directions. When your route target is in another zone, the info panel shows how to get there (walk, Deeprun Tram, boat, zeppelin, flight master). `/path travel` prints the full steps; `/path travel chat` turns the automatic zone-change message on or off.

## 4.7.2
- Fix: Lua error at Realm.lua:34 (GetItemInfo missing on newer clients; now uses C_Item.GetItemInfo first).
- Fix: "also accept off-route quests" is off by default, and quest hand-in no longer depends on it.
