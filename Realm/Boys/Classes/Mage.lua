local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Mage", color = "ff69ccf0", accent = { .41, .8, .94 }, extrasTitle = "Armors and portals",
  specOrder = { "ARCANE", "FIRE", "FROST" }, defaultSpec = "FROST",
  gear = {
    armorSubclasses = { [0] = true, [1] = true },
    weaponSubclasses = { [7] = true, [10] = true, [15] = true, [19] = true },
    holdable = true, ranged = true,
  },
  specs = {
    ARCANE = {
      name = "Arcane", role = "DPS",
      summary = "Mana burst caster. Arcane Blast stacks a damage buff but uses more mana each cast, Arcane Missiles channels, and Arcane Power and Presence of Mind add burst.",
      statPriority = "Spell Damage > Intellect > Crit > Hit",
      weights = Wt("caster", { INT = 1, CRIT = 1 }),
      opener = { "Arcane Intellect, armor, then buff yourself.", "Arcane Power and Presence of Mind.", "Arcane Blast stacks, then Arcane Missiles." },
      priority = {
        { "Arcane Intellect", "Intellect buff for the group." },
        { "Mage Armor", "Keep an armor on.", alt = "Frost Armor" },
        { "Arcane Power", "Big damage window." },
        { "Presence of Mind", "Instant next cast." },
        { "Arcane Blast", "Main spell. Stacks a buff and costs more." },
        { "Arcane Missiles", "Channel filler." },
        { "Arcane Explosion", "Close AoE." },
        { "Evocation", "Refill mana." },
        { "Counterspell", "Interrupt." },
      },
      aoe = { { "Arcane Explosion", "Close AoE." }, { "Blizzard", "Ground AoE." } },
      cooldowns = {
        { "Arcane Power", "burst", "Damage window." }, { "Presence of Mind", "burst", "Instant cast." },
        { "Evocation", "utility", "Refill mana." }, { "Ice Block", "defensive", "Immunity." },
        { "Counterspell", "utility", "Interrupt." },
      },
      tips = { "Watch mana. Arcane Blast gets expensive.", "Evocation when low.", "Counterspell interrupts.", "Burn mana in short windows." },
    },
    FIRE = {
      name = "Fire", role = "DPS",
      summary = "Crit-driven fire caster. Fireball is your filler, Frostfire Bolt adds slow, Pyroblast and Scorch add pressure, and Combustion stacks crit for a burst.",
      statPriority = "Fire Damage > Crit > Hit > Intellect",
      weights = Wt("caster", { TIP_SCHOOL_FIRE = 1, CRIT = 1.4 }),
      opener = { "Armor and Arcane Intellect.", "Scorch for the debuff if the group needs it.", "Fireball, Combustion in your window." },
      priority = {
        { "Arcane Intellect", "Intellect buff for the group." },
        { "Molten Armor", "Crit armor.", alt = "Mage Armor" },
        { "Combustion", "Crit stacking burst." },
        { "Scorch", "Fire debuff and cheap filler." },
        { "Fireball", "Main filler." },
        { "Frostfire Bolt", "New hybrid bolt, adds slow." },
        { "Fire Blast", "Instant." },
        { "Pyroblast", "Big opener." },
        { "Living Bomb", "DoT, if available." },
        { "Counterspell", "Interrupt." },
      },
      aoe = { { "Flamestrike", "Ground AoE." }, { "Blast Wave", "Close AoE." }, { "Arcane Explosion", "Close AoE." } },
      cooldowns = {
        { "Combustion", "burst", "Crit burst." }, { "Ice Block", "defensive", "Immunity." },
        { "Evocation", "utility", "Refill mana." }, { "Counterspell", "utility", "Interrupt." },
      },
      tips = { "Keep Scorch debuff up if it is needed.", "Frostfire Bolt is new in Forever.", "Counterspell interrupts.", "Kite with slows." },
    },
    FROST = {
      name = "Frost", role = "DPS",
      summary = "Control and steady damage. Frostbolt slows, Ice Lance hits when Fingers of Frost procs, Frozen Orb and Cone of Cold help groups, and Ice Barrier and Frost Nova keep you alive. Great for solo.",
      statPriority = "Frost Damage > Hit > Crit > Intellect",
      weights = Wt("caster", { TIP_SCHOOL_FROST = 1, INT = .5 }),
      opener = { "Armor, Arcane Intellect.", "Ice Barrier before the pull.", "Frostbolt, Ice Lance with Fingers of Frost." },
      priority = {
        { "Arcane Intellect", "Intellect buff for the group." },
        { "Ice Armor", "Frost armor.", alt = "Frost Armor" },
        { "Ice Barrier", "Absorb shield." },
        { "Icy Veins", "Haste burst." },
        { "Frostbolt", "Main filler. Slows." },
        { "Ice Lance", "Instant, hits harder with Fingers of Frost." },
        { "Frostfire Bolt", "Hybrid bolt." },
        { "Cone of Cold", "Close slow and damage." },
        { "Frost Nova", "Root nearby enemies." },
        { "Counterspell", "Interrupt." },
      },
      aoe = { { "Blizzard", "Ground AoE." }, { "Cone of Cold", "Close AoE." }, { "Frost Nova", "Root nearby enemies." } },
      cooldowns = {
        { "Icy Veins", "burst", "Haste burst." }, { "Cold Snap", "burst", "Reset frost cooldowns." },
        { "Ice Block", "defensive", "Immunity." }, { "Ice Barrier", "defensive", "Absorb shield." },
        { "Evocation", "utility", "Refill mana." },
      },
      tips = { "Kite with Frost Nova and Frostbolt.", "Ice Lance when Fingers of Frost procs.", "Ice Barrier before pulling.", "Counterspell interrupts." },
    },
  },
  utility = {
    { "Blink", "utility", "Short teleport." }, { "Polymorph", "utility", "Crowd control." },
    { "Counterspell", "utility", "Interrupt." }, { "Frost Nova", "utility", "Root nearby enemies." },
    { "Ice Block", "defensive", "Immunity." }, { "Evocation", "utility", "Refill mana." },
    { "Remove Curse", "utility", "Remove a curse." }, { "Slow Fall", "utility", "Float down safely." },
    { "Conjure Food", "utility", "Make food." }, { "Conjure Water", "utility", "Make water." },
    { "Teleport: Stormwind", "utility", "Teleport to Stormwind." }, { "Teleport: Orgrimmar", "utility", "Teleport to Orgrimmar." },
    { "Portal: Stormwind", "utility", "Portal to Stormwind." }, { "Portal: Orgrimmar", "utility", "Portal to Orgrimmar." },
  },
  extras = {
    "Armors: Mage, Molten, Frost, Ice. Keep one on.",
    "Conjure food and water, and trade them to your group.",
    "Polymorph a target to sheep it. Do not hit it.",
    "Mages wear cloth only. Wands help when mana is low.",
  },
}
TB.UseStdPro(def, "cloth")
TB.RegisterClass("MAGE", def)
