local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Paladin", color = "fff58cba", accent = { .96, .55, .73 }, extrasTitle = "Auras and blessings",
  specOrder = { "HOLY", "PROTECTION", "RETRIBUTION" }, defaultSpec = "RETRIBUTION",
  gear = {
    armorSubclasses = { [0] = true, [4] = true, [6] = true }, lowArmor = { 3, 40 },
    weaponSubclasses = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true },
    shield = true, relicSubclass = 7,
  },
  specs = {
    HOLY = {
      name = "Holy", role = "Healer",
      summary = "The best single-target healer in Forever. Holy Shock and Flash of Light are your fast heals, Holy Light is the big one, and Divine Favor and Lay on Hands save the day.",
      statPriority = "Healing Power > MP5 > Intellect > Crit",
      weights = Wt("healer", { INT = .5, MP5 = 1.3 }),
      opener = { "Aura and blessings on the group.", "Judgement of Light or Wisdom on the boss.", "Holy Shock and Flash of Light on the tank." },
      priority = {
        { "Blessing of Kings", "Keep your group buff up." },
        { "Judgement", "Refresh a helpful Judgement on the target." },
        { "Holy Shock", "Instant heal, on cooldown." },
        { "Flash of Light", "Fast, cheap heal." },
        { "Holy Light", "Big heal. Use when you have time." },
        { "Divine Favor", "Guaranteed crit on your next heal." },
        { "Lay on Hands", "Emergency full heal." },
        { "Cleanse", "Remove poison, disease and magic." },
        { "Divine Illumination", "Cheaper heals for a short time, if you have it." },
      },
      aoe = { { "Consecration", "Free damage while you wait." } },
      cooldowns = {
        { "Divine Favor", "burst", "Crit heal." }, { "Lay on Hands", "defensive", "Emergency heal." },
        { "Divine Shield", "defensive", "Immunity." }, { "Divine Protection", "defensive", "Damage reduction." },
        { "Blessing of Protection", "defensive", "Physical immunity for an ally." }, { "Divine Intervention", "utility", "Sacrifice yourself to save an ally." },
      },
      tips = { "Choose the right Blessing for your group.", "Use Holy Shock on cooldown.", "Stand close, Light heals are short range.", "Save Lay on Hands for real emergencies." },
    },
    PROTECTION = {
      name = "Protection", role = "Tank",
      summary = "Shield tank. Holy Shield and Consecration make threat for groups, Seal of Fury now taunts at 10 yards, and Templar's Bulwark adds survival.",
      statPriority = "Stamina > Defense > Armor > Block Value > Spell Power",
      weights = Wt("tank", { STA = 1.3, DEF = 4, SP = .3, HEAL = .1 }),
      opener = { "Righteous Fury, Devotion Aura, shield up.", "Pull with Seal of Fury or your ranged hit.", "Holy Shield, Consecration, Judgement." },
      priority = {
        { "Righteous Fury", "Required for threat. Keep it on." },
        { "Holy Shield", "On cooldown. Block and threat." },
        { "Seal of Fury", "New Prot seal. Taunt at 10 yards." },
        { "Seal of Righteousness", "Standard threat seal." },
        { "Judgement", "Keep up on the target." },
        { "Consecration", "Your AoE threat. Stand in it." },
        { "Templar's Bulwark", "New defensive talent." },
        { "Hammer of Justice", "Stun." },
        { "Blessing of Sanctuary", "Reduces damage you take." },
      },
      aoe = { { "Consecration", "Your group threat." }, { "Holy Wrath", "Damage to undead and demons." } },
      cooldowns = {
        { "Divine Shield", "defensive", "Immunity." }, { "Divine Protection", "defensive", "Damage reduction." },
        { "Lay on Hands", "defensive", "Emergency heal." }, { "Holy Shield", "defensive", "Block boost." },
        { "Blessing of Protection", "defensive", "Physical immunity for an ally." }, { "Hammer of Justice", "utility", "Stun." },
      },
      tips = { "Keep Righteous Fury on.", "Holy Shield on cooldown.", "Consecration is your threat on groups.", "You can taunt at 10 yards with Seal of Fury." },
    },
    RETRIBUTION = {
      name = "Retribution", role = "DPS",
      summary = "Two-handed holy melee. Seal of Command procs your big hits, Judgement keeps pressure on, and Crusader Strike or Hammer of Wrath finish. Mana is your limit, so manage it.",
      statPriority = "Attack Power > Strength > Crit > Hit",
      weights = Wt("melee", { STR = 2.2, SP = .3, DPS = 14 }),
      opener = { "Aura, Seal of Command or Righteousness.", "Judgement, then auto-attack.", "Consecration and Crusader Strike if you have it." },
      priority = {
        { "Seal of Command", "Your main seal. Procs big hits." },
        { "Judgement", "Use when the seal is up." },
        { "Crusader Strike", "Use if your version has it." },
        { "Hammer of Wrath", "Use on low health targets." },
        { "Exorcism", "Damage to undead and demons." },
        { "Consecration", "Free damage when mana allows." },
        { "Repentance", "Incapacitate a target." },
        { "Sanctity Aura", "Boosts Holy damage for the group." },
        { "Retribution Aura", "Damage to attackers." },
      },
      aoe = { { "Consecration", "Your AoE." }, { "Holy Wrath", "Damage to undead and demons." } },
      cooldowns = {
        { "Divine Favor", "burst", "Damage window with crits." }, { "Avenging Wrath", "burst", "Damage window if you have it." },
        { "Divine Shield", "defensive", "Immunity." }, { "Lay on Hands", "defensive", "Emergency heal." },
        { "Hammer of Justice", "utility", "Stun." }, { "Blessing of Freedom", "utility", "Break roots." },
      },
      tips = { "Seal then Judgement is your core loop.", "Hammer of Wrath is an execute.", "Watch mana. Use Seal of Wisdom or Blessing of Wisdom when low.", "Use the slowest two-hander you can." },
    },
  },
  utility = {
    { "Divine Shield", "defensive", "Immunity, with a long penalty." }, { "Lay on Hands", "defensive", "Emergency heal." },
    { "Blessing of Protection", "defensive", "Physical immunity for an ally." }, { "Blessing of Freedom", "utility", "Break roots." },
    { "Blessing of Sacrifice", "defensive", "Take an ally's damage." }, { "Hammer of Justice", "utility", "Stun." },
    { "Cleanse", "utility", "Remove poison, disease and magic." }, { "Purify", "utility", "Remove poison and disease." },
    { "Redemption", "utility", "Resurrect out of combat." }, { "Divine Intervention", "utility", "Save an ally." },
    { "Turn Undead", "utility", "Fear undead." }, { "Sense Undead", "utility", "Track undead." },
  },
  extras = {
    "Auras: Devotion, Retribution, Concentration, Sanctity, Crusader. Pick what your group needs.",
    "Blessings are your group tools: Kings, Might, Wisdom, Salvation, Sanctuary, Light.",
    "Seals set your attack. Judgement spends it for an effect.",
    "Undead Paladins are new in Forever.",
  },
}
TB.UseStdPro(def, "plate")
TB.RegisterClass("PALADIN", def)
