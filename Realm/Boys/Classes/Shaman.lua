local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Shaman", color = "ff0070de", accent = { 0, .44, .87 }, extrasTitle = "Totems and shields",
  specOrder = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" }, defaultSpec = "ENHANCEMENT",
  gear = {
    armorSubclasses = { [0] = true, [2] = true, [3] = true, [6] = true }, lowArmor = { 2, 40 },
    weaponSubclasses = { [0] = true, [1] = true, [4] = true, [5] = true, [10] = true, [13] = true, [15] = true },
    shield = true, holdable = true, dualWield = true, relicSubclass = 9,
  },
  specs = {
    ELEMENTAL = {
      name = "Elemental", role = "DPS",
      summary = "Lightning and fire caster. Lightning Bolt and Chain Lightning are your main hits, Flame Shock keeps a DoT, Earth Shock interrupts, and Elemental Mastery guarantees a crit.",
      statPriority = "Spell Damage > Crit > Hit > Intellect",
      weights = Wt("caster", { INT = .5, CRIT = 1.2 }),
      opener = { "Lightning Shield, totems down.", "Flame Shock then Lightning Bolt.", "Chain Lightning on groups." },
      priority = {
        { "Lightning Shield", "Your self-buff." },
        { "Elemental Mastery", "Guaranteed crit." },
        { "Flame Shock", "DoT, keep it up." },
        { "Lightning Bolt", "Main filler." },
        { "Chain Lightning", "Hits several targets." },
        { "Earth Shock", "Interrupt and burst." },
        { "Fire Nova Totem", "AoE burst." },
        { "Searing Totem", "Extra fire damage." },
      },
      aoe = { { "Chain Lightning", "Hits several targets." }, { "Fire Nova Totem", "AoE totem." } },
      cooldowns = {
        { "Elemental Mastery", "burst", "Guaranteed crit." }, { "Bloodlust", "burst", "Haste for the group, if you have it." },
        { "Grounding Totem", "defensive", "Absorb a harmful spell." }, { "Earth Shock", "utility", "Interrupt." },
      },
      tips = { "Place the right totems before pulling.", "Move away from melee when you can.", "Earth Shock interrupts.", "Hit chance matters." },
    },
    ENHANCEMENT = {
      name = "Enhancement", role = "DPS",
      summary = "Melee Shaman. Dual-wield with Windfury weapon procs, Stormstrike for burst, and shocks for ranged damage. Totems and Lightning Shield add support.",
      statPriority = "Attack Power > Agility > Hit > Crit",
      weights = Wt("melee", { AGI = 1.6, STR = 1, DPS = 12, TIP_HIT = 14 }),
      opener = { "Windfury and Flametongue on your weapons.", "Totems down, Lightning Shield.", "Stormstrike then Earth Shock." },
      priority = {
        { "Lightning Shield", "Self-buff." },
        { "Windfury Weapon", "Main hand proc, big hits." },
        { "Flametongue Weapon", "Fire damage on off hand." },
        { "Stormstrike", "On cooldown." },
        { "Earth Shock", "Instant shock." },
        { "Flame Shock", "DoT." },
        { "Feral Spirit", "Wolf allies for a window." },
        { "Shamanistic Rage", "Mana and damage reduction." },
        { "Searing Totem", "Extra fire damage." },
      },
      aoe = { { "Fire Nova Totem", "AoE." }, { "Magma Totem", "Close AoE." } },
      cooldowns = {
        { "Feral Spirit", "burst", "Wolf allies." }, { "Bloodlust", "burst", "Haste for the group, if you have it." },
        { "Shamanistic Rage", "defensive", "Mana and damage reduction." }, { "Earth Shock", "utility", "Interrupt." },
      },
      tips = { "Pick the right weapon imbues.", "Totems matter more than any rotation.", "Hit cap helps a lot.", "Earth Shock interrupts." },
    },
    RESTORATION = {
      name = "Restoration", role = "Healer",
      summary = "Totem healer. Chain Heal bounces between allies, Healing Wave is the big heal, Lesser Healing Wave is fast, and Mana Tide Totem keeps the group casting.",
      statPriority = "Healing Power > MP5 > Intellect > Crit",
      weights = Wt("healer", { INT = .5, MP5 = 1.2 }),
      opener = { "Water Shield, totems down.", "Healing Stream Totem and Mana Spring Totem.", "Chain Heal on groups, Healing Wave on tanks." },
      priority = {
        { "Water Shield", "Mana return." },
        { "Healing Stream Totem", "Free background healing." },
        { "Mana Spring Totem", "Mana for the group." },
        { "Earth Shield", "Heals on hit for a target, if available." },
        { "Chain Heal", "Bouncing heal." },
        { "Healing Wave", "Big heal." },
        { "Lesser Healing Wave", "Fast heal." },
        { "Mana Tide Totem", "Group mana refill." },
        { "Cure Poison", "Remove poison.", alt = "Cure Toxins" },
        { "Cure Disease", "Remove disease." },
      },
      aoe = { { "Chain Heal", "Bounces between allies." }, { "Healing Stream Totem", "Steady healing." } },
      cooldowns = {
        { "Mana Tide Totem", "burst", "Mana for the group." }, { "Nature's Swiftness", "burst", "Instant big heal." },
        { "Bloodlust", "burst", "Haste for the group." }, { "Grounding Totem", "defensive", "Absorb a harmful spell." },
      },
      tips = { "Drop your totems at the group's feet.", "Chain Heal works best on groups.", "Use Nature's Swiftness in emergencies.", "Stay in range of your totems." },
    },
  },
  utility = {
    { "Ghost Wolf", "utility", "Move faster." }, { "Earthbind Totem", "utility", "Slow enemies." },
    { "Grounding Totem", "defensive", "Absorb a harmful spell." }, { "Purge", "utility", "Remove enemy buffs." },
    { "Cure Poison", "utility", "Remove poison." }, { "Cure Disease", "utility", "Remove disease." },
    { "Reincarnation", "utility", "Return after death." }, { "Astral Recall", "utility", "Teleport home." },
    { "Frost Shock", "utility", "Slow and damage." }, { "Earth Shock", "utility", "Interrupt." },
    { "Tremor Totem", "utility", "Break fear and charm." }, { "Water Walking", "utility", "Walk on water." },
  },
  extras = {
    "Totems: Earth, Fire, Water, Air. Drop one of each for a group.",
    "Shields: Lightning, Water, Earth. Keep one on you.",
    "Weapon imbues: Windfury, Flametongue, Frostbrand, Rockbiter.",
    "Shamans can wear leather and mail, and mail from level 40.",
  },
}
TB.UseStdPro(def, "mail")
TB.RegisterClass("SHAMAN", def)
