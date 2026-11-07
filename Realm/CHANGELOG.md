# Realm changelog

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
