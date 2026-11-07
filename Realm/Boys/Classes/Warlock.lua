local ADDON, ns = ...
local TB = ns.TB
local Wt = TB.Weights

local def = {
  name = "Warlock", color = "ff8788ee", accent = { .53, .53, .93 }, extrasTitle = "Demons and curses",
  specOrder = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" }, defaultSpec = "DESTRUCTION",
  gear = { armorSubclasses = { [0] = true, [1] = true }, weaponSubclasses = { [15] = true, [7] = true, [10] = true, [19] = true }, holdable = true },
  specs = {
    AFFLICTION = {
      name = "Affliction", role = "DPS",
      summary = "Stack Shadow damage-over-time effects and let them tick. In Forever your DoTs can critically strike, and Wrack, the 31-point talent, is your filler channel.",
      statPriority = "Spell Power (Shadow) > Crit > Hit > Spirit for Life Tap",
      weights = Wt("caster", { TIP_SCHOOL_SHADOW = .9, SPI = .12 }),
      opener = { "Pet out, Life Tap to full mana before the pull.", "Open with your Bane and Corruption, then Siphon Life.", "Then Wrack or Shadow Bolt to fill while the DoTs tick." },
      priority = {
        { "Curse of the Elements", "Keep one raid-wide Curse on the boss. Now it boosts all magic damage." },
        { "Bane of Agony", "Your main Bane. Only one Bane per Warlock can be on a target.", alt = "Curse of Agony" },
        { "Amplify Curse", "Press before Bane of Agony for 50% more damage." },
        { "Corruption", "Keep it up. Instant, so cast it while moving." },
        { "Siphon Life", "Keep it up if talented. It heals you." },
        { "Immolate", "Add it if you have spare time and want Fire support." },
        { "Wrack", "Capstone channel. Your other Shadow DoTs hit 10% harder while you channel it." },
        { "Shadow Bolt", "Strong filler, close behind Wrack." },
        { "Drain Soul", "Use on low health targets, and to make a Soul Shard." },
        { "Life Tap", "Turn health into mana when you are low. Spirit makes it stronger here." },
      },
      aoe = { { "Seed of Corruption", "AoE Corruption if your version has it." }, { "Rain of Fire", "Channel on packs." }, { "Hellfire", "Close-range AoE. Costs you health." } },
      cooldowns = {
        { "Amplify Curse", "burst", "Boosts your next Bane." }, { "Death Coil", "defensive", "Horror and heal." },
        { "Fear", "utility", "Crowd control." }, { "Howl of Terror", "utility", "AoE fear." },
      },
      tips = { "DoTs can crit in Forever, so spell crit helps them too.", "Life Tap before you are empty, not after.", "Spirit makes Life Tap better in this version.", "Keep one Bane and one Curse up if you can." },
    },
    DEMONOLOGY = {
      name = "Demonology", role = "DPS",
      summary = "You and your demon share the damage. Your pet scales from your stats, Soul Link spreads damage, and Demonic Pact lets you sacrifice one demon and keep another out. Below 35% health Decimation makes Soul Fire free.",
      statPriority = "Spell Power (Fire or Shadow) > Hit > Crit > Stamina",
      weights = Wt("caster", { TIP_SCHOOL_SHADOW = .9, TIP_SCHOOL_FIRE = .9, STA = .3 }),
      opener = { "Summon your demon, then Soul Link.", "Shadow Bolt or Searing Pain to apply Demonic Brand.", "Keep casting your main spell while your demon attacks." },
      priority = {
        { "Summon Felguard", "Strong melee demon, if you have the talent." },
        { "Summon Voidwalker", "Tanky demon. Good for leveling and for dungeons.", alt = "Summon Felhunter" },
        { "Soul Link", "Shares damage with your demon, keeping you alive." },
        { "Fel Domination", "Instantly resummon your demon in a fight." },
        { "Demonic Pact", "Sacrifice one demon, keep another out. Boosts your damage." },
        { "Searing Pain", "Applies Demonic Brand so your pet's next attacks hit harder." },
        { "Soul Fire", "Free and faster under 35% health with Decimation." },
        { "Shadow Bolt", "Your main filler." },
        { "Life Tap", "Turn health into mana." },
        { "Health Funnel", "Heal your demon." },
      },
      aoe = { { "Rain of Fire", "AoE channel." }, { "Hellfire", "Close AoE. Your pet draws less." }, { "Inferno", "Summon an Infernal to tank." } },
      cooldowns = {
        { "Fel Domination", "burst", "Instant demon." }, { "Death Coil", "defensive", "Horror and heal." },
        { "Soulstone", "utility", "Self rez before the pull." }, { "Fear", "utility", "Crowd control." },
      },
      tips = { "Your demon scales from your gear, so keep it alive.", "Use Health Funnel between pulls.", "Keep a Soulstone on yourself or a healer.", "Under 35% health, spam Soul Fire." },
    },
    DESTRUCTION = {
      name = "Destruction", role = "DPS",
      summary = "Hard-hitting Fire and Shadow. Immolate and Conflagrate keep Immolate on the target and grant a Shadow bonus, Shadowburn gives a Fire bonus, and Incinerate, the 30-point capstone, hits 25% harder with Immolate up.",
      statPriority = "Spell Power (Fire) > Crit > Hit",
      weights = Wt("caster", { TIP_SCHOOL_FIRE = .9, TIP_SCHOOL_SHADOW = .9, CRIT = .9, TIP_SPELL_CRIT = 12 }),
      opener = { "Pet out, Life Tap to full mana.", "Open with Immolate, then Conflagrate.", "Incinerate or Shadow Bolt to fill, Shadowburn to finish." },
      priority = {
        { "Curse of the Elements", "Raid-wide magic damage boost on the boss." },
        { "Bane of Havoc", "Copies 15% of your damage to a second target. Great on cleave." },
        { "Immolate", "Keep it on the target. It powers Incinerate." },
        { "Conflagrate", "Burns your Immolate for damage and gives you a Shadow bonus." },
        { "Shadowburn", "Execute with a Soul Shard. Gives a Fire bonus." },
        { "Soul Fire", "Big hit. Cast when you can afford the cast time." },
        { "Incinerate", "Your Fire filler. Stronger with Immolate up.", alt = "Searing Pain" },
        { "Shadow Bolt", "Filler, or when you need Shadow damage." },
        { "Life Tap", "Turn health into mana." },
      },
      aoe = { { "Rain of Fire", "AoE channel." }, { "Hellfire", "Close-range AoE." }, { "Shadowfury", "Stun and damage if your version has it." } },
      cooldowns = {
        { "Conflagrate", "burst", "Short cooldown, use it." }, { "Shadowburn", "burst", "Execute button." },
        { "Death Coil", "defensive", "Horror and heal." }, { "Fear", "utility", "Crowd control." },
      },
      tips = { "Do not let Immolate drop, Incinerate and Conflagrate need it.", "Save Shadowburn for low health targets.", "Fire and Brimstone and Shadow and Flame link your two schools.", "Keep Life Tap up so you never run dry." },
    },
  },
  utility = {
    { "Shadow Ward", "defensive", "Absorb shadow damage." }, { "Death Coil", "defensive", "Horror and heal." },
    { "Fear", "utility", "Crowd control." }, { "Howl of Terror", "utility", "AoE fear." },
    { "Banish", "utility", "Crowd control for demons and elementals." }, { "Enslave Demon", "utility", "Take control of a demon." },
    { "Soulstone", "utility", "Self resurrect on someone, set before the pull." },
    { "Create Healthstone", "utility", "Make Healthstones for the group." },
    { "Ritual of Summoning", "utility", "Summon your group." }, { "Eye of Kilrogg", "utility", "Scout ahead." },
    { "Detect Invisibility", "utility", "See invisible things." },
  },
  extras = {
    "Imp: ranged fire. Safe for soloing.", "Voidwalker: tanky, takes hits for you.",
    "Succubus: crowd control and burst damage.", "Felhunter: Spell Lock interrupt and magic dispel.",
    "Felguard: strong melee demon from the Demonology tree.",
    "Banes (Agony, Doom) and Curses (Elements, Weakness, Tongues) are separate. You can use one of each on a target.",
  },
}
TB.UseStdPro(def, "cloth", {
  { name = "Engineering + Tailoring", goal = "Highest damage", why = "Engineering bombs and gadgets with Tailoring for your own cloth gear. Strong damage and utility.", needs = { "Engineering", "Tailoring" } },
  { name = "Enchanting + Tailoring", goal = "The easy pairing", why = "Make your own cloth gear and enchant it. Disenchant what you outgrow.", needs = { "Enchanting", "Tailoring" } },
})
TB.RegisterClass("WARLOCK", def)
