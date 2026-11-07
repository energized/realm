local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Druid", color = "ffff7d0a", accent = { 1, .49, .04 }, extrasTitle = "Forms",
  specOrder = { "BALANCE", "FERAL", "RESTORATION" }, defaultSpec = "FERAL",
  gear = {
    armorSubclasses = { [0] = true, [2] = true },
    weaponSubclasses = { [15] = true, [13] = true, [4] = true, [5] = true, [6] = true, [10] = true },
    holdable = true, relicSubclass = 8,
  },
  specs = {
    BALANCE = {
      name = "Balance", role = "DPS",
      summary = "Ranged caster. Eclipse makes you alternate Wrath and Starfire, Moonfire and Insect Swarm sit on the target, and Moonkin Form gives the raid spell and physical crit.",
      statPriority = "Spell Power > Crit > Hit > Intellect",
      weights = Wt("caster", { TIP_SCHOOL_NATURE = .9, TIP_SCHOOL_ARCANE = .9, INT = .45, SPI = .12 }),
      opener = { "Moonkin Form, Faerie Fire on the target.", "Insect Swarm and Moonfire.", "Then Wrath and Starfire to trigger Eclipse." },
      priority = {
        { "Moonkin Form", "Raid-wide crit and armor. Keep it on." },
        { "Faerie Fire", "Baseline now. Keep it on the target." },
        { "Insect Swarm", "Balance DoT. Keep it up." },
        { "Moonfire", "Instant damage and a DoT." },
        { "Starfire", "Hits hard. Cast it after Wrath for Eclipse." },
        { "Wrath", "Cheaper filler. It shortens your next Starfire." },
        { "Innervate", "Big mana restore. Use on yourself or a healer." },
      },
      aoe = { { "Hurricane", "Channel on packs." }, { "Starfall", "Talented AoE if your version has it." } },
      cooldowns = {
        { "Innervate", "burst", "Mana burst." }, { "Barkskin", "defensive", "Damage reduction." },
        { "Nature's Grasp", "defensive", "Roots attackers." }, { "Rebirth", "utility", "Battle resurrection." },
      },
      tips = { "Alternate Wrath and Starfire so Eclipse triggers.", "Moonkin Form gives raid crit, so keep it on even in raids.", "Faerie Fire is now baseline.", "Innervate yourself when low, or a healer." },
    },
    FERAL = {
      name = "Feral", role = "DPS or Tank",
      summary = "Cat to damage, bear to tank. Cat builds combo points and spends them on Ferocious Bite or bleeds, and Shifting Power replaces powershifting. Bear uses Swipe, the new Primal Bite and Lacerate for threat.",
      statPriority = "Attack Power > Agility > Strength > Crit > Hit",
      weights = Wt("melee", { FAP = 1, AP = .5, STR = 1.2, AGI = 2 }),
      opener = { "Cat Form, Prowl and sneak in.", "Pounce or Ravage from stealth.", "Rake, then build combo points and Ferocious Bite." },
      priority = {
        { "Tiger's Fury", "Energy and damage boost. Keep it on." },
        { "Faerie Fire (Feral)", "Armor reduction. Baseline now.", alt = "Faerie Fire" },
        { "Rake", "Keep the bleed up. Rend and Tear rewards bleeds." },
        { "Rip", "Finisher bleed at 5 combo points." },
        { "Ferocious Bite", "Finisher. Predatory Discipline keeps your leftover energy." },
        { "Shred", "Builder from behind the target." },
        { "Claw", "Builder when you cannot get behind." },
        { "Berserk", "Capstone damage window, if talented." },
        { "Shifting Power", "Replaces powershifting. Refills your energy." },
      },
      aoe = { { "Swipe", "AoE for cat or bear." }, { "Rake", "Spread it." } },
      cooldowns = {
        { "Berserk", "burst", "Big damage window." }, { "Tiger's Fury", "burst", "Short energy burst." },
        { "Frenzied Regeneration", "defensive", "Bear heal." }, { "Enrage", "burst", "Rage in bear." },
        { "Barkskin", "defensive", "Damage reduction." }, { "Dash", "utility", "Sprint." },
      },
      tips = { "Cat: bleeds first, then Ferocious Bite.", "Bear: Lacerate and Primal Bite keep threat.", "Use Shifting Power instead of powershifting.", "Bear tanks use health and armor, not block or parry." },
    },
    RESTORATION = {
      name = "Restoration", role = "Healer",
      summary = "HoT healer. HoTs stack and can crit, Wild Growth heals a group, Swiftmend no longer consumes your HoT, and Bloom heals when a HoT ends.",
      statPriority = "Healing Power > MP5 > Spirit > Intellect > Crit",
      weights = Wt("healer", { SPI = .5, INT = .5 }),
      opener = { "Rejuvenation on the tank.", "Wild Growth when the group is hurt.", "Swiftmend for a fast burst." },
      priority = {
        { "Rejuvenation", "Your core HoT. Keep it on whoever is taking damage." },
        { "Regrowth", "Fast heal plus a HoT." },
        { "Wild Growth", "AoE HoT. New in Forever." },
        { "Swiftmend", "Burst heal, keeps your HoT now." },
        { "Healing Touch", "Big, efficient heal." },
        { "Nature's Swiftness", "Instant heal for panic moments." },
        { "Innervate", "Mana boost. Use it on yourself or a healer." },
        { "Tranquility", "Channeled group heal." },
        { "Revive", "Out-of-combat resurrection. New in Forever." },
      },
      aoe = { { "Wild Growth", "Group HoT." }, { "Tranquility", "Big channel." } },
      cooldowns = {
        { "Nature's Swiftness", "burst", "Instant heal." }, { "Innervate", "burst", "Mana." },
        { "Tranquility", "burst", "Group heal." }, { "Barkskin", "defensive", "Damage reduction." },
        { "Swiftmend", "burst", "Burst heal." },
      },
      tips = { "HoTs crit now, so spread them early.", "Swiftmend keeps the HoT, use it freely.", "Innervate when mana is low.", "Remove Curse and Abolish Poison are your dispels." },
    },
  },
  utility = {
    { "Barkskin", "defensive", "Damage reduction." }, { "Frenzied Regeneration", "defensive", "Bear self heal." },
    { "Nature's Grasp", "defensive", "Roots attackers." }, { "Rebirth", "utility", "Battle resurrection." },
    { "Innervate", "utility", "Mana for a healer or yourself." }, { "Dash", "utility", "Cat sprint." },
    { "Feral Charge", "utility", "Charge and interrupt in bear or cat." }, { "Bash", "utility", "Stun in bear." },
    { "Entangling Roots", "utility", "Root." }, { "Hibernate", "utility", "Put a beast to sleep." },
    { "Soothe Animal", "utility", "Remove a beast enrage." }, { "Remove Curse", "utility", "Cleanse curses." },
    { "Abolish Poison", "utility", "Cleanse poisons." }, { "Prowl", "utility", "Stealth." },
    { "Mark of the Wild", "utility", "Group buff." }, { "Thorns", "utility", "Damage to attackers." },
  },
  extras = {
    "Bear Form: tank form from a quest. Rage and attack power.",
    "Cat Form: damage, energy and combo points. Needed for Dash, Prowl and Cower.",
    "Moonkin Form: Balance capstone. Armor and raid crit, uses mana.",
    "Travel Form: instant speed, comes 10 levels before a mount.",
    "Shapeshifting frees you from polymorph and movement impairment, and you can use consumables while shifted.",
  },
}
TB.UseStdPro(def, "leather", {
  { name = "Herbalism + Alchemy", goal = "Best for Druids", why = "Gather herbs in Travel Form, brew potions you can use while shifted, and use the new camp recipes.", needs = { "Herbalism", "Alchemy" } },
  { name = "Leatherworking + Skinning", goal = "Dress yourself", why = "Make your own leather gear from your own leather. Leveling gear and endgame pieces.", needs = { "Leatherworking", "Skinning" } },
})
TB.RegisterClass("DRUID", def)
