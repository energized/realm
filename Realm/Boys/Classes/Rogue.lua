local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Rogue", color = "fffff569", accent = { 1, .96, .41 }, extrasTitle = "Poisons and stealth",
  specOrder = { "ASSASSINATION", "COMBAT", "SUBTLETY" }, defaultSpec = "COMBAT",
  gear = {
    armorSubclasses = { [0] = true, [2] = true },
    weaponSubclasses = { [0] = true, [4] = true, [7] = true, [13] = true, [15] = true, [2] = true, [3] = true, [18] = true, [16] = true },
    dualWield = true, ranged = true, thrown = true,
  },
  specs = {
    ASSASSINATION = {
      name = "Assassination", role = "DPS",
      summary = "Poisons and daggers. Mutilate strikes with both daggers, hits harder on poisoned targets and awards 2 combo points. You need two daggers for it. Keep Slice and Dice up and finish with Eviscerate.",
      statPriority = "Attack Power > Agility > Crit > Hit",
      weights = Wt("melee", { AGI = 2, STR = 1, DPS = 8 }),
      opener = { "Stealth in with daggers and poisons applied.", "Cheap Shot or Garrote, then Mutilate.", "Slice and Dice, then finish with Eviscerate." },
      priority = {
        { "Slice and Dice", "Keep it up. Big attack speed." },
        { "Cold Blood", "Guaranteed crit on your next finisher." },
        { "Mutilate", "Needs two daggers. Hits with both and gives 2 combo points." },
        { "Rupture", "Bleed finisher on tougher targets." },
        { "Eviscerate", "Your damage finisher at 5 points." },
        { "Envenom", "Poison finisher if your version has it." },
        { "Sinister Strike", "Builder if you cannot use Mutilate." },
        { "Kidney Shot", "Stun for control." },
      },
      aoe = { { "Blade Flurry", "Cleave if you have it." }, { "Eviscerate", "Single-target finisher." } },
      cooldowns = {
        { "Cold Blood", "burst", "Guaranteed crit." }, { "Vanish", "defensive", "Escape and reopen." },
        { "Evasion", "defensive", "Dodge boost." }, { "Sprint", "utility", "Speed burst." },
        { "Preparation", "burst", "Reset cooldowns." },
      },
      tips = { "Both weapons must be daggers for Mutilate.", "Keep Slice and Dice up at all times.", "Sap no longer breaks stealth, so use it freely.", "Kick interrupts." },
    },
    COMBAT = {
      name = "Combat", role = "DPS",
      summary = "Sustained melee. Sinister Strike builds points, Slice and Dice and Eviscerate spend them, Blade Flurry cleaves, and Adrenaline Rush is the big window. Hack and Slash now adds one-handed axes.",
      statPriority = "Attack Power > Agility > Hit > Crit",
      weights = Wt("melee", { AGI = 2, STR = 1, HIT = 1.4, TIP_HIT = 14, DPS = 12 }),
      opener = { "Stealth in, Cheap Shot or Ambush.", "Slice and Dice at 1-2 points.", "Sinister Strike to 5 points, Eviscerate." },
      priority = {
        { "Slice and Dice", "Keep it up." },
        { "Adrenaline Rush", "Big energy and damage window." },
        { "Blade Flurry", "Cleave. Use on two or more targets." },
        { "Sinister Strike", "Main builder." },
        { "Eviscerate", "Damage finisher at 5 points." },
        { "Expose Armor", "Armor reduction on bosses." },
        { "Riposte", "Use after a parry." },
        { "Kick", "Interrupt." },
        { "Gouge", "Short control." },
      },
      aoe = { { "Blade Flurry", "Cleave your attacks." }, { "Eviscerate", "Finisher." } },
      cooldowns = {
        { "Adrenaline Rush", "burst", "Damage window." }, { "Blade Flurry", "burst", "Cleave." },
        { "Evasion", "defensive", "Dodge boost." }, { "Sprint", "utility", "Speed burst." },
        { "Vanish", "defensive", "Escape." },
      },
      tips = { "Hack and Slash works with swords, axes, maces and fists in Forever.", "Hit cap helps a lot.", "Sap no longer breaks stealth.", "Kick interrupts." },
    },
    SUBTLETY = {
      name = "Subtlety", role = "DPS",
      summary = "Stealth and burst. Backstab and Ambush from behind, Hemorrhage to apply bleed, Premeditation to pre-load combo points, and Preparation to reset your tools.",
      statPriority = "Attack Power > Agility > Crit > Hit",
      weights = Wt("melee", { AGI = 2, STR = 1, TIP_CRIT = 16, DPS = 12 }),
      opener = { "Premeditation, then stealth in from behind.", "Ambush or Backstab.", "Slice and Dice, then Eviscerate." },
      priority = {
        { "Premeditation", "Pre-load combo points before an opener." },
        { "Slice and Dice", "Keep it up." },
        { "Ambush", "Stealth opener, hits hard from behind." },
        { "Backstab", "Main builder from behind. Needs a dagger." },
        { "Hemorrhage", "Builder and bleed debuff." },
        { "Ghostly Strike", "Dodge boost and damage." },
        { "Eviscerate", "Finisher." },
        { "Preparation", "Reset your cooldowns." },
        { "Shadowstep", "Teleport behind a target, if you have it." },
      },
      aoe = { { "Blade Flurry", "Cleave if you have it." } },
      cooldowns = {
        { "Preparation", "burst", "Resets Vanish, Evasion and more." }, { "Vanish", "defensive", "Escape and reopen." },
        { "Evasion", "defensive", "Dodge boost." }, { "Sprint", "utility", "Speed burst." },
        { "Cold Blood", "burst", "Guaranteed crit." },
      },
      tips = { "Get behind the target for Backstab.", "Premeditation before the opener.", "Vanish and re-open for extra burst.", "Sap no longer breaks stealth." },
    },
  },
  utility = {
    { "Evasion", "defensive", "Dodge boost." }, { "Vanish", "defensive", "Disappear." },
    { "Sprint", "utility", "Speed burst." }, { "Kick", "utility", "Interrupt." },
    { "Kidney Shot", "utility", "Stun with combo points." }, { "Cheap Shot", "utility", "Stealth stun." },
    { "Gouge", "utility", "Short control." }, { "Blind", "utility", "Crowd control." },
    { "Sap", "utility", "Crowd control, no longer breaks stealth." }, { "Distract", "utility", "Lure enemies." },
    { "Pick Pocket", "utility", "Steal from humanoids." }, { "Feint", "defensive", "Reduce threat." },
    { "Stealth", "utility", "Get the first hit." },
  },
  extras = {
    "Poisons: apply Instant, Deadly or Crippling to your weapons. They last longer in Forever.",
    "Stealth makes your first hit much stronger.",
    "Sap is baseline and no longer breaks stealth.",
    "Rogues can wear leather only.",
  },
}
TB.UseStdPro(def, "leather", {
  { name = "Skinning + Leatherworking", goal = "Dress yourself", why = "Make your own leather gear. Skin the leather as you quest.", needs = { "Skinning", "Leatherworking" } },
})
TB.RegisterClass("ROGUE", def)
