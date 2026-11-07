local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Hunter", color = "ffabd473", accent = { .67, .83, .45 }, extrasTitle = "Pets and aspects",
  specOrder = { "BEASTMASTERY", "MARKSMANSHIP", "SURVIVAL" }, defaultSpec = "MARKSMANSHIP",
  gear = {
    armorSubclasses = { [0] = true, [3] = true }, lowArmor = { 2, 40 },
    weaponSubclasses = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true, [7] = true, [8] = true, [10] = true, [13] = true, [15] = true, [18] = true },
    dualWield = true, ranged = true,
  },
  specs = {
    BEASTMASTERY = {
      name = "Beast Mastery", role = "DPS",
      summary = "Pet-focused. Your pet does a large share of the damage, Bestial Wrath makes it ferocious, and unique pet family abilities give you extra tools. Great for solo play.",
      statPriority = "Ranged Attack Power > Agility > Crit > Hit",
      weights = Wt("ranged", { AGI = 2, DPS = 14 }),
      opener = { "Pet out, Hunter's Mark on the target.", "Open at range with Aimed Shot, then Auto Shot.", "Bestial Wrath on your pet for burst." },
      priority = {
        { "Aspect of the Hawk", "Standard damage aspect." },
        { "Hunter's Mark", "Keep it on the target." },
        { "Bestial Wrath", "Burst your pet." },
        { "Kill Command", "Pet damage. Use after a crit." },
        { "Intimidation", "Pet stun." },
        { "Aimed Shot", "Baseline now, big shot." },
        { "Arcane Shot", "Instant filler." },
        { "Multi-Shot", "Group damage." },
        { "Serpent Sting", "DoT when you have time." },
        { "Mend Pet", "Keep your pet alive." },
      },
      aoe = { { "Multi-Shot", "Group damage." }, { "Explosive Trap", "AoE trap, usable in combat now." }, { "Volley", "AoE channel if your version has it." } },
      cooldowns = {
        { "Bestial Wrath", "burst", "Pet burst." }, { "Rapid Fire", "burst", "Attack speed burst." },
        { "Intimidation", "burst", "Pet stun." }, { "Deterrence", "defensive", "Dodge and parry boost." },
        { "Feign Death", "defensive", "Drop threat." }, { "Disengage", "defensive", "Jump back." },
      },
      tips = { "Keep your pet alive, it is your damage.", "Feed and heal your pet.", "Pets have unique family abilities in Forever.", "Traps can be used in combat now." },
    },
    MARKSMANSHIP = {
      name = "Marksmanship", role = "DPS",
      summary = "Pure ranged damage. Aimed Shot is baseline, Sniper Shot adds a precise hit, and Auto Shot with weaving Arcane Shot keeps you steady. Great at a distance.",
      statPriority = "Ranged Attack Power > Agility > Crit > Hit",
      weights = Wt("ranged", { AGI = 2, DPS = 16, TIP_CRIT = 16 }),
      opener = { "Hunter's Mark, Trueshot Aura.", "Open with Aimed Shot, then Auto Shot.", "Rapid Fire for burst." },
      priority = {
        { "Aspect of the Hawk", "Standard damage aspect." },
        { "Trueshot Aura", "Raid attack power buff." },
        { "Hunter's Mark", "Keep it on the target." },
        { "Rapid Fire", "Attack speed burst." },
        { "Aimed Shot", "Baseline big shot." },
        { "Sniper Shot", "New precise hit." },
        { "Multi-Shot", "Group damage." },
        { "Arcane Shot", "Instant filler between Auto Shots." },
        { "Scatter Shot", "Disorient a target." },
      },
      aoe = { { "Multi-Shot", "Group damage." }, { "Explosive Trap", "AoE trap." } },
      cooldowns = {
        { "Rapid Fire", "burst", "Burst." }, { "Deterrence", "defensive", "Dodge and parry boost." },
        { "Feign Death", "defensive", "Drop threat." }, { "Disengage", "defensive", "Jump back." },
      },
      tips = { "Do not clip your Auto Shot.", "Stand still for big shots.", "Keep Hunter's Mark and Trueshot Aura up.", "Use Feign Death if you get aggro." },
    },
    SURVIVAL = {
      name = "Survival", role = "DPS",
      summary = "Melee, traps and bleeds. Survival leans into melee attacks now: Strider Kick hits on a short cooldown, and traps can be placed in combat.",
      statPriority = "Attack Power > Agility > Crit > Hit",
      weights = Wt("ranged", { AGI = 2, AP = 1, STR = .5, DPS = 14 }),
      opener = { "Pet out, Hunter's Mark.", "Lay a trap and open with a sting.", "Close to melee with Raptor Strike and Strider Kick." },
      priority = {
        { "Aspect of the Hawk", "Damage aspect.", alt = "Aspect of the Monkey" },
        { "Hunter's Mark", "Keep it on the target." },
        { "Explosive Trap", "Burn damage, now usable in combat." },
        { "Immolation Trap", "Fire DoT." },
        { "Serpent Sting", "Keep the DoT up." },
        { "Strider Kick", "New melee attack on an 8 second cooldown." },
        { "Raptor Strike", "Melee hit." },
        { "Mongoose Bite", "Use after a dodge." },
        { "Wyvern Sting", "Sleep and DoT." },
        { "Deterrence", "Dodge and parry boost." },
      },
      aoe = { { "Explosive Trap", "AoE damage." }, { "Multi-Shot", "Group damage." } },
      cooldowns = {
        { "Rapid Fire", "burst", "Burst." }, { "Deterrence", "defensive", "Dodge and parry boost." },
        { "Feign Death", "defensive", "Drop threat." }, { "Disengage", "defensive", "Jump back." },
        { "Freezing Trap", "utility", "Crowd control." },
      },
      tips = { "Traps are usable in combat now.", "Get your Strider Kick on cooldown.", "Keep your pet alive.", "Counterattack after a parry." },
    },
  },
  utility = {
    { "Deterrence", "defensive", "Dodge and parry boost." }, { "Feign Death", "defensive", "Drop threat." },
    { "Disengage", "utility", "Jump back." }, { "Freezing Trap", "utility", "Crowd control." },
    { "Frost Trap", "utility", "Slow enemies." }, { "Scare Beast", "utility", "Fear a beast." },
    { "Concussive Shot", "utility", "Slow a target." }, { "Distracting Shot", "utility", "Pull aggro to you." },
    { "Scatter Shot", "utility", "Disorient a target." }, { "Mend Pet", "utility", "Heal your pet." },
    { "Revive Pet", "utility", "Bring back your pet." }, { "Call Pet", "utility", "Summon your pet." },
    { "Misdirection", "utility", "Send threat to a tank." },
  },
  extras = {
    "Foxes are a new pet family in Forever.",
    "Pet families have unique abilities now.",
    "Aspects: Hawk (damage), Monkey (defense), Cheetah/Pack (speed), Viper (mana) where available.",
    "Human Hunters are new in Forever.",
  },
}
TB.UseStdPro(def, "mail", {
  { name = "Skinning + Leatherworking", goal = "Dress yourself", why = "Make your own leather and mail gear from your own leather.", needs = { "Skinning", "Leatherworking" } },
})
TB.RegisterClass("HUNTER", def)
