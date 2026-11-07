-- TheBoys / Realm macros: per-spec spell slots used to build the five hotbar macro sets.
-- Spells are plain NAMES (never "Rank N"), so a macro always casts the highest rank the character knows.
-- "A|B" means: use A when known, otherwise B. List the NEWEST or replacement spell first.
-- Spells the character does not know yet are skipped when the macros are built.
--
-- Slots:  st single target   fin finisher   dot damage over time   aoe multi-target   burst cooldowns
--         def defensive      int interrupt  cc crowd control       taunt            heal self/any heal
--         heal1 fast heal    heal2 big heal hot heal over time     aoeheal group heal  dispel
--         buff buffs/auras   mob mobility    open opener/summon    util utility   main = extra spells for the main bar
-- Flags:  atk "m" melee auto-attack, "r" ranged auto shot; pet = true sends the pet in; style "mod" (shift/ctrl
--         alternates, for casters with an always-ready filler) or "prio" (first usable spell fires, for cooldown-gated melee).
--
-- SOURCE: Wowhead "WoW: Forever" class guides, rotation + cooldown page of every spec, read 2026-11-07
-- (https://www.wowhead.com/forever/guide/classes/<class>/<spec>/rotation-cooldowns-pve-<dps|tank|healer>).
-- Spells those guides list in the rotation/cooldown slots are used. Spells that exist only in later expansions and are
-- not in the Forever guides were removed from the rotation slots (Crusader Strike, Kill Command, Envenom, Devastate,
-- Vampiric Touch, Mind Sear, Shadowfiend, Dispersion, Seed of Corruption, Shadowfury, Starfall, Earth Shield).
-- Defensive, crowd-control and utility slots are guide-silent and still come from the Realm class guides.
-- Still open: WoWDB (no Forever data reachable), and Assassination Rogue (the guide names one builder only by spell id).
local ADDON, ns = ...
local TB = ns.TB

TB.MacroDataVersion = 2
TB.MacroSource = "Wowhead WoW: Forever class guides (rotation pages, read 2026-11-07) + Realm class guides for defensive/utility slots; WoWDB cross-check pending"

local D = {}

D.WARRIOR = {
  ARMS = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Arms Warrior rotation guide, updated 2026/11/04",
    st = "Execute;Mortal Strike;Overpower;Slam;Rend;Heroic Strike", aoe = "Sweeping Strikes;Whirlwind;Cleave",
    burst = "Recklessness;Bloodrage", def = "Retaliation", int = "Pummel|Shield Bash",
    cc = "Intimidating Shout", mob = "Charge;Intercept;Hamstring", buff = "Battle Shout",
    util = "Victory Rush;Thunder Clap;Demoralizing Shout", main = "Spearing Strike;Sunder Armor" },
  FURY = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Fury Warrior rotation guide, checked 2026-11-07",
    st = "Execute;Bloodthirst;Whirlwind;Overpower;Heroic Strike", aoe = "Whirlwind;Cleave;Sweeping Strikes",
    burst = "Death Wish;Recklessness;Bloodrage;Berserker Rage", def = "Retaliation", int = "Pummel|Shield Bash",
    cc = "Intimidating Shout", mob = "Intercept;Charge;Hamstring", buff = "Battle Shout",
    util = "Victory Rush;Sunder Armor" },
  PROTECTION = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Protection Warrior tank rotation guide, checked 2026-11-07",
    st = "Shield Slam;Revenge;Bloodthirst;Sunder Armor;Heroic Strike", aoe = "Thunder Clap;Cleave",
    burst = "Retaliation;Bloodrage", def = "Shield Block;Shield Wall;Last Stand", int = "Shield Bash|Pummel",
    cc = "Concussion Blow;Intimidating Shout", mob = "Charge;Intercept", buff = "Battle Shout",
    taunt = "Taunt;Challenging Shout", util = "Demoralizing Shout;Rend;Victory Rush" },
}

D.PALADIN = {
  HOLY = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Holy Paladin healer rotation guide, checked 2026-11-07",
    st = "Judgement;Holy Shock", aoe = "Consecration", heal1 = "Flash of Light", heal2 = "Holy Light",
    hot = "Holy Shock", aoeheal = "Light's Vigil", dispel = "Cleanse|Purify", burst = "Divine Favor;Divine Illumination",
    def = "Divine Protection;Divine Shield", cc = "Hammer of Justice", mob = "Blessing of Freedom",
    buff = "Greater Blessing of Kings|Blessing of Kings;Greater Blessing of Might|Blessing of Might;Concentration Aura",
    heal = "Flash of Light;Holy Light", util = "Lay on Hands", open = "Seal of Light|Seal of Wisdom" },
  PROTECTION = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Protection Paladin tank rotation guide, checked 2026-11-07",
    st = "Judgement;Holy Shield;Holy Strike;Holy Shock;Consecration;Exorcism;Hammer of Wrath", aoe = "Consecration;Holy Wrath",
    burst = "Avenging Wrath", def = "Holy Shield;Divine Protection;Divine Shield", cc = "Hammer of Justice",
    mob = "Blessing of Freedom", buff = "Righteous Fury;Retribution Aura;Blessing of Sanctuary",
    taunt = "Righteous Defense", heal = "Flash of Light;Holy Light", util = "Lay on Hands",
    open = "Seal of Fury|Seal of Righteousness" },
  RETRIBUTION = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Retribution Paladin rotation guide, checked 2026-11-07",
    st = "Judgement;Holy Strike;Hammer of Wrath;Exorcism", aoe = "Consecration;Holy Wrath",
    burst = "Avenging Wrath;Divine Favor", def = "Divine Protection;Divine Shield", cc = "Hammer of Justice",
    mob = "Blessing of Freedom", buff = "Blessing of Kings;Blessing of Might", heal = "Flash of Light;Holy Light",
    util = "Repentance", open = "Seal of Command|Seal of Righteousness" },
}

D.HUNTER = {
  BEASTMASTERY = { atk = "r", pet = true, style = "prio", verified = "Wowhead WoW: Forever, Beast Mastery Hunter rotation guide, checked 2026-11-07 (Summon Hawk is named in the guide; not confirmed in game)",
    st = "Summon Hawk;Arcane Shot;Aimed Shot", aoe = "Multi-Shot;Volley;Explosive Trap",
    dot = "Serpent Sting", burst = "Bestial Wrath;Rapid Fire;Intimidation", def = "Deterrence;Feign Death",
    cc = "Freezing Trap;Scatter Shot", mob = "Disengage;Aspect of the Cheetah", buff = "Aspect of the Hawk;Trueshot Aura",
    heal = "Mend Pet", util = "Hunter's Mark;Tranquilizing Shot" },
  MARKSMANSHIP = { atk = "r", pet = true, style = "prio", verified = "Wowhead WoW: Forever, Marksmanship Hunter rotation guide, updated 2026/11/04 (single-target and AoE checked 2026-11-07)",
    st = "Arcane Shot;Aimed Shot;Sniper Shot", aoe = "Multi-Shot;Volley;Explosive Trap", dot = "Serpent Sting",
    burst = "Rapid Fire", def = "Deterrence;Feign Death", cc = "Freezing Trap;Scatter Shot",
    mob = "Disengage;Aspect of the Cheetah", buff = "Aspect of the Hawk;Trueshot Aura", heal = "Mend Pet",
    util = "Hunter's Mark;Tranquilizing Shot" },
  SURVIVAL = { atk = "m", pet = true, style = "prio", verified = "Wowhead WoW: Forever, Survival Hunter rotation guide, updated 2026/10/30 (full melee; weaving section is still 'work in progress' on Wowhead)",
    st = "Raptor Strike;Mongoose Bite;Strider Kick;Immolation Trap;Summon Hawk", aoe = "Multi-Shot;Volley;Explosive Trap",
    dot = "Serpent Sting", burst = "Rapid Fire", def = "Deterrence;Feign Death", cc = "Freezing Trap;Wyvern Sting",
    mob = "Disengage;Aspect of the Cheetah", buff = "Aspect of the Hawk|Aspect of the Monkey;Trueshot Aura",
    heal = "Mend Pet", util = "Hunter's Mark;Tranquilizing Shot" },
}

D.ROGUE = {
  -- Assassination: the Wowhead guide lists its builder only by spell id 1310707 (name not readable), so the old
  -- "Mutilate|Sinister Strike" builder is kept and flagged as unconfirmed.
  ASSASSINATION = { atk = "m", style = "mod", verified = "Wowhead WoW: Forever, Assassination Rogue rotation guide, checked 2026-11-07 (PARTIAL: builder spell unnamed in guide)",
    st = "Mutilate|Sinister Strike", fin = "Eviscerate", aoe = "Blade Flurry", burst = "Cold Blood;Blade Flurry",
    def = "Evasion;Vanish", int = "Kick", cc = "Kidney Shot;Gouge", mob = "Sprint;Shadowstep",
    buff = "Slice and Dice", open = "Cheap Shot;Ambush", util = "Preparation" },
  COMBAT = { atk = "m", style = "mod", verified = "Wowhead WoW: Forever, Combat Rogue rotation guide, checked 2026-11-07",
    st = "Sinister Strike|Backstab", fin = "Eviscerate", aoe = "Blade Flurry", burst = "Adrenaline Rush;Blade Flurry",
    def = "Evasion;Vanish", int = "Kick", cc = "Gouge;Kidney Shot", mob = "Sprint",
    buff = "Slice and Dice", open = "Cheap Shot;Ambush", util = "Riposte" },
  SUBTLETY = { atk = "m", style = "mod", verified = "Wowhead WoW: Forever, Subtlety Rogue rotation guide, checked 2026-11-07",
    st = "Hemorrhage;Backstab;Ghostly Strike", fin = "Rupture;Eviscerate", aoe = "Blade Flurry",
    burst = "Premeditation;Preparation;Cold Blood", def = "Evasion;Vanish", int = "Kick", cc = "Kidney Shot;Gouge",
    mob = "Shadowstep;Sprint", buff = "Slice and Dice", open = "Garrote;Premeditation;Ambush;Cheap Shot",
    util = "Shadowstep" },
}

D.PRIEST = {
  DISCIPLINE = { style = "mod", verified = "Wowhead WoW: Forever, Discipline Priest healer rotation guide, checked 2026-11-07",
    st = "Shadow Word: Pain;Smite", dot = "Shadow Word: Pain", aoe = "Holy Nova",
    heal1 = "Penance;Heal;Flash Heal", heal2 = "Greater Heal", hot = "Power Word: Shield;Renew;Prayer of Mending",
    aoeheal = "Prayer of Healing;Holy Nova", dispel = "Dispel Magic;Cure Disease", burst = "Inner Focus;Power Infusion",
    def = "Fade;Desperate Prayer", cc = "Psychic Scream", buff = "Power Word: Fortitude;Inner Fire",
    heal = "Power Word: Shield;Heal;Flash Heal", mob = "Levitate", util = "Fear Ward" },
  HOLY = { style = "mod", verified = "Wowhead WoW: Forever, Holy Priest healer rotation guide, checked 2026-11-07",
    st = "Holy Fire;Smite", dot = "Shadow Word: Pain", aoe = "Holy Nova",
    heal1 = "Heal;Flash Heal", heal2 = "Greater Heal", hot = "Renew;Prayer of Mending",
    aoeheal = "Prayer of Healing;Holy Nova;Circle of Healing", dispel = "Dispel Magic;Cure Disease",
    burst = "Inner Focus;Divine Hymn", def = "Fade;Desperate Prayer", cc = "Psychic Scream",
    buff = "Power Word: Fortitude;Inner Fire", heal = "Heal;Flash Heal;Greater Heal", mob = "Levitate",
    util = "Binding Heal;Power Word: Shield" },
  SHADOW = { style = "mod", verified = "Wowhead WoW: Forever, Shadow Priest rotation guide, checked 2026-11-07",
    st = "Mind Blast;Shadow Word: Death;Mind Flay", dot = "Shadow Word: Pain;Devouring Plague", aoe = "Mind Flay;Holy Nova",
    burst = "Vampiric Embrace", def = "Fade;Desperate Prayer", cc = "Psychic Scream;Shackle Undead",
    buff = "Shadowform;Power Word: Fortitude;Inner Fire", heal = "Power Word: Shield;Flash Heal",
    mob = "Levitate", util = "Mind Control" },
}

D.SHAMAN = {
  ELEMENTAL = { style = "mod", verified = "Wowhead WoW: Forever, Elemental Shaman rotation guide, updated 2026/11/04 (single-target and AoE checked 2026-11-07)",
    st = "Lightning Bolt;Chain Lightning;Earth Shock", dot = "Flame Shock", aoe = "Chain Lightning;Fire Nova;Magma Totem",
    burst = "Lightning Mastery;Elemental Mastery;Bloodlust", def = "Grounding Totem", int = "Earth Shock", cc = "Frost Shock",
    buff = "Lightning Shield;Water Shield;Strength of Earth Totem;Windfury Totem", heal = "Healing Wave;Lesser Healing Wave",
    mob = "Ghost Wolf", util = "Searing Totem" },
  ENHANCEMENT = { atk = "m", style = "prio", verified = "Wowhead WoW: Forever, Enhancement Shaman rotation guide, checked 2026-11-07",
    st = "Stormstrike;Earth Shock;Lightning Bolt;Fire Nova", dot = "Flame Shock", aoe = "Magma Totem;Fire Nova",
    burst = "Rage of the Farseer;Feral Spirit;Bloodlust;Shamanistic Rage", def = "Shamanistic Rage;Grounding Totem", int = "Earth Shock",
    cc = "Frost Shock", buff = "Lightning Shield;Windfury Weapon;Flametongue Weapon;Strength of Earth Totem",
    heal = "Healing Wave;Lesser Healing Wave", mob = "Ghost Wolf", util = "Searing Totem" },
  RESTORATION = { style = "mod", verified = "Wowhead WoW: Forever, Restoration Shaman healer rotation guide, checked 2026-11-07",
    st = "Lightning Bolt;Earth Shock", dot = "Flame Shock", aoe = "Fire Nova;Chain Lightning",
    heal1 = "Riptide;Lesser Healing Wave", heal2 = "Healing Wave", hot = "Riptide", aoeheal = "Chain Heal",
    dispel = "Cure Poison|Cure Toxins;Cure Disease", burst = "Nature's Swiftness;Mana Tide Totem;Bloodlust",
    def = "Grounding Totem", int = "Earth Shock", cc = "Frost Shock",
    buff = "Water Shield;Mana Spring Totem;Strength of Earth Totem;Windfury Totem",
    heal = "Lesser Healing Wave;Healing Wave", mob = "Ghost Wolf", util = "Healing Stream Totem;Earthbind Totem" },
}

D.MAGE = {
  ARCANE = { style = "mod", verified = "Wowhead WoW: Forever, Arcane Mage rotation guide, checked 2026-11-07",
    st = "Arcane Blast;Arcane Missiles;Arcane Wrath;Fire Blast;Scorch", aoe = "Arcane Explosion;Flamestrike;Blizzard",
    burst = "Arcane Power;Presence of Mind", def = "Ice Barrier;Ice Block", int = "Counterspell", cc = "Polymorph",
    mob = "Blink", buff = "Arcane Intellect;Mage Armor|Frost Armor", util = "Evocation", open = "Arcane Blast" },
  FIRE = { style = "mod", verified = "Wowhead WoW: Forever, Fire Mage rotation guide, checked 2026-11-07",
    st = "Pyroblast;Fire Blast;Scorch;Fireball;Frostfire Bolt;Arcane Missiles", aoe = "Flamestrike;Blast Wave;Arcane Explosion",
    burst = "Combustion", def = "Ice Barrier;Ice Block", int = "Counterspell", cc = "Polymorph", mob = "Blink",
    buff = "Arcane Intellect;Molten Armor|Mage Armor", util = "Evocation", open = "Pyroblast" },
  FROST = { style = "mod", verified = "Wowhead WoW: Forever, Frost Mage rotation guide, updated 2026/11/02 (re-checked 2026-11-07)",
    st = "Frostbolt;Ice Lance;Cone of Cold", aoe = "Blizzard;Cone of Cold;Frost Nova",
    burst = "Cold Snap;Icy Veins", def = "Ice Barrier;Ice Block", int = "Counterspell", cc = "Polymorph",
    mob = "Blink", buff = "Arcane Intellect;Ice Armor|Frost Armor", util = "Frost Nova;Evocation", open = "Frostbolt" },
}

D.WARLOCK = {
  AFFLICTION = { pet = true, style = "mod", verified = "Wowhead WoW: Forever, Affliction Warlock rotation guide, checked 2026-11-07",
    st = "Wrack;Shadow Bolt;Life Tap", dot = "Corruption;Bane of Doom|Bane of Agony|Curse of Agony;Siphon Life;Immolate",
    aoe = "Rain of Fire;Hellfire", burst = "Amplify Curse", def = "Death Coil",
    int = "Spell Lock", cc = "Fear;Banish", buff = "Demon Armor|Demon Skin;Curse of the Elements;Curse of Recklessness",
    heal = "Health Funnel", util = "Life Tap", open = "Summon Felhunter|Summon Voidwalker" },
  DEMONOLOGY = { pet = true, style = "mod", verified = "Wowhead WoW: Forever, Demonology Warlock rotation guide, checked 2026-11-07 (guide names the pet Sayaad; summon spell not confirmed)",
    st = "Searing Pain;Soul Fire;Shadow Bolt", dot = "Corruption;Immolate;Bane of Doom|Bane of Agony", aoe = "Hellfire;Rain of Fire",
    burst = "Fel Domination", def = "Death Coil", int = "Spell Lock", cc = "Fear;Banish",
    buff = "Demon Armor|Demon Skin;Soul Link;Curse of the Elements;Curse of Recklessness", heal = "Health Funnel", util = "Life Tap",
    open = "Summon Felguard;Summon Felhunter|Summon Voidwalker" },
  DESTRUCTION = { pet = true, style = "mod", verified = "Wowhead WoW: Forever, Destruction Warlock rotation guide, checked 2026-11-07",
    st = "Conflagrate;Shadowburn;Incinerate|Searing Pain;Shadow Bolt", dot = "Immolate;Corruption;Bane of Doom|Bane of Agony",
    aoe = "Hellfire;Rain of Fire", burst = "Amplify Curse", def = "Death Coil",
    int = "Spell Lock", cc = "Fear;Banish", buff = "Demon Armor|Demon Skin;Curse of the Elements;Curse of Recklessness",
    heal = "Health Funnel", util = "Life Tap", open = "Summon Imp|Summon Voidwalker" },
}

D.DRUID = {
  BALANCE = { style = "mod", verified = "Wowhead WoW: Forever, Balance Druid rotation guide, checked 2026-11-07",
    st = "Wrath;Starfire", dot = "Moonfire;Insect Swarm", aoe = "Hurricane", burst = "Innervate",
    def = "Barkskin;Nature's Grasp", cc = "Entangling Roots;Hibernate", buff = "Mark of the Wild;Thorns",
    heal = "Regrowth;Rejuvenation;Healing Touch", util = "Faerie Fire" },
  FERAL = { atk = "m", style = "mod", verified = "Wowhead WoW: Forever, Feral Druid DPS rotation guide, checked 2026-11-07 (tank guide not checked for taunt or threat order)",
    st = "Shred;Claw", fin = "Rip;Ferocious Bite", dot = "Rake", aoe = "Swipe",
    burst = "Berserk;Tiger's Fury;Enrage", def = "Barkskin;Frenzied Regeneration", int = "Feral Charge",
    cc = "Bash;Entangling Roots", mob = "Dash;Feral Charge", buff = "Mark of the Wild;Thorns",
    taunt = "Growl", heal = "Regrowth;Healing Touch", open = "Prowl", util = "Shifting Power;Faerie Fire (Feral)|Faerie Fire" },
  RESTORATION = { style = "mod", verified = "Wowhead WoW: Forever, Restoration Druid healer rotation guide, checked 2026-11-07",
    st = "Wrath;Moonfire", dot = "Moonfire", aoe = "Hurricane",
    heal1 = "Regrowth", heal2 = "Healing Touch", hot = "Rejuvenation;Swiftmend", aoeheal = "Wild Growth;Tranquility",
    dispel = "Remove Curse;Abolish Poison", burst = "Nature's Swiftness;Innervate", def = "Barkskin",
    cc = "Entangling Roots;Hibernate", mob = "Dash", buff = "Mark of the Wild;Thorns",
    heal = "Regrowth;Rejuvenation;Healing Touch", util = "Tranquility" },
}

TB.MacroData = D
