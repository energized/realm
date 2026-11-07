local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Priest", color = "ffffffff", accent = { .9, .9, 1 }, extrasTitle = "Shadow and light",
  specOrder = { "DISCIPLINE", "HOLY", "SHADOW" }, defaultSpec = "HOLY",
  gear = {
    armorSubclasses = { [0] = true, [1] = true },
    weaponSubclasses = { [4] = true, [10] = true, [15] = true, [19] = true },
    holdable = true, ranged = true,
  },
  specs = {
    DISCIPLINE = {
      name = "Discipline", role = "Healer",
      summary = "Shield and support healer. Power Word: Shield soaks damage, Inner Focus and Power Infusion boost casting, and Penance-style tools vary by version. Great for steady, efficient group healing.",
      statPriority = "Healing Power > MP5 > Intellect > Spirit",
      weights = Wt("healer", { INT = .6, SPI = .4, MP5 = 1.2 }),
      opener = { "Fortitude and Inner Fire on the group.", "Power Word: Shield the tank before the pull.", "Renew and Flash Heal as needed." },
      priority = {
        { "Power Word: Fortitude", "Stamina buff for the group." },
        { "Inner Fire", "Armor and spell power for you." },
        { "Power Word: Shield", "Soak damage. Watch Weakened Soul." },
        { "Inner Focus", "Free next spell." },
        { "Power Infusion", "Boost an ally's casting." },
        { "Renew", "Cheap heal over time." },
        { "Flash Heal", "Fast heal." },
        { "Greater Heal", "Efficient big heal." },
        { "Dispel Magic", "Remove magic effects." },
        { "Prayer of Mending", "Bouncing heal if your version has it." },
      },
      aoe = { { "Prayer of Healing", "Group heal." }, { "Holy Nova", "Small heal and damage around you." } },
      cooldowns = {
        { "Inner Focus", "burst", "Free next spell." }, { "Power Infusion", "burst", "Boost an ally." },
        { "Fade", "defensive", "Drop threat." }, { "Desperate Prayer", "defensive", "Emergency self-heal." },
        { "Psychic Scream", "utility", "Fear nearby enemies." },
      },
      tips = { "Shield early, heal late.", "Weakened Soul limits Shield on the same target.", "Mana efficiency is your strength.", "Fade when you pull threat." },
    },
    HOLY = {
      name = "Holy", role = "Healer",
      summary = "The strongest group healer. Greater Heal and Flash Heal cover single targets, Circle of Healing and Prayer of Healing cover groups, and Lightwell and Spirit of Redemption add support.",
      statPriority = "Healing Power > MP5 > Intellect > Spirit",
      weights = Wt("healer", { INT = .5, SPI = .5, MP5 = 1.2 }),
      opener = { "Fortitude and Inner Fire.", "Renew on the tank.", "Greater Heal and Flash Heal as needed." },
      priority = {
        { "Power Word: Fortitude", "Stamina buff." },
        { "Inner Fire", "Armor and spell power." },
        { "Renew", "Cheap heal over time." },
        { "Flash Heal", "Fast heal." },
        { "Greater Heal", "Efficient big heal." },
        { "Circle of Healing", "Group heal, on cooldown." },
        { "Prayer of Healing", "Party heal." },
        { "Holy Nova", "Small heal and damage around you." },
        { "Dispel Magic", "Remove magic effects." },
        { "Cure Disease", "Remove disease." },
      },
      aoe = { { "Prayer of Healing", "Party heal." }, { "Circle of Healing", "Group heal." }, { "Holy Nova", "Close group heal." } },
      cooldowns = {
        { "Divine Hymn", "burst", "Big group heal." }, { "Inner Focus", "burst", "Free next spell." },
        { "Fade", "defensive", "Drop threat." }, { "Desperate Prayer", "defensive", "Emergency self-heal." },
        { "Psychic Scream", "utility", "Fear nearby enemies." },
      },
      tips = { "Do not overheal. Pick the right spell size.", "Renew the tank before the pull.", "Back off when mana is low.", "Fade when you pull threat." },
    },
    SHADOW = {
      name = "Shadow", role = "DPS",
      summary = "Damage over time caster. Shadow Word: Pain and Vampiric Touch tick, Mind Flay and Mind Blast fill, and Shadowform boosts your shadow power. Vampiric Embrace heals your group.",
      statPriority = "Shadow Damage > Hit > Crit > Spirit",
      weights = Wt("caster", { TIP_SCHOOL_SHADOW = 1, SPI = .3 }),
      opener = { "Shadowform and Inner Fire.", "Shadow Word: Pain and Vampiric Touch.", "Mind Blast on cooldown, Mind Flay otherwise." },
      priority = {
        { "Shadowform", "Stay in it. Shadow damage up." },
        { "Inner Fire", "Armor and spell power." },
        { "Vampiric Embrace", "Heals your party from your damage." },
        { "Shadow Word: Pain", "Keep the DoT up." },
        { "Vampiric Touch", "DoT that returns mana." },
        { "Mind Blast", "On cooldown." },
        { "Mind Flay", "Filler channel." },
        { "Shadow Word: Death", "Execute with a cost." },
        { "Smite", "Filler if Shadowform is not available." },
        { "Psychic Scream", "Fear nearby enemies." },
      },
      aoe = { { "Mind Sear", "Channel on groups if your version has it." }, { "Holy Nova", "Small group damage." } },
      cooldowns = {
        { "Mind Blast", "burst", "On cooldown." }, { "Vampiric Embrace", "utility", "Party healing." },
        { "Fade", "defensive", "Drop threat." }, { "Psychic Scream", "utility", "Fear nearby enemies." },
        { "Dispersion", "defensive", "Damage reduction and mana, if you have it." },
      },
      tips = { "Keep DoTs rolling, then Mind Flay.", "Hit chance matters for shadow spells.", "Fade if you pull threat.", "Sit back at the edge of the group." },
    },
  },
  utility = {
    { "Power Word: Shield", "defensive", "Soak damage." }, { "Fade", "defensive", "Drop threat." },
    { "Psychic Scream", "utility", "Fear nearby enemies." }, { "Shackle Undead", "utility", "Hold an undead." },
    { "Mind Control", "utility", "Take control of a humanoid." }, { "Dispel Magic", "utility", "Remove magic." },
    { "Cure Disease", "utility", "Remove disease." }, { "Levitate", "utility", "Float over water and gaps." },
    { "Resurrection", "utility", "Resurrect out of combat." }, { "Mind Vision", "utility", "See through a target's eyes." },
    { "Desperate Prayer", "defensive", "Emergency self-heal." },
  },
  extras = {
    "Inner Fire: armor and spell power. Keep it on.",
    "Shadowform boosts shadow damage but blocks Holy spells.",
    "Priests wear cloth only.",
    "Wands are your ranged option when mana runs out.",
  },
}
TB.UseStdPro(def, "cloth")
TB.RegisterClass("PRIEST", def)
