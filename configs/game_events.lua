--[[
    game_events — the EVENT -> REACTIONS registry (config-as-code).

    Code fires a named gameplay event (GameEvents.fire("level_up", ctx)); THIS config decides what
    reacts. Each reaction kind is a key the client dispatcher (src/Client/Systems/GameEvents.lua)
    knows how to apply:

        sound = "<key in configs/sounds.lua>"   -- play that sound on its configured bus
        -- (planned) vfx = "<CombatFX/effect spec>", toast = "<text>", ...

    Add or extend a row to react to an event WITHOUT touching the firing code; remove a row to
    silence it. The only inherently-code part is detecting the event and calling fire().

    Event sources:
      level_up   — the player's claimed level increased        (client: LevelUpController)
    Planned (wire the source, then add a row here): death, hit, area_change, egg_hatch, purchase.
]]

return {
    level_up = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 255, 205, 70 } }, -- gold celebratory burst at the player
    },

    -- A new area/gate was unlocked (client: init.client ZoneUnlockResult ok). Celebratory, and no
    -- prior fanfare, so no conflict with existing reactions.
    area_unlocked = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 120, 230, 150 } }, -- green "new ground" burst
    },

    -- ===== Batch 1: server-fired celebrations (FireGameEvent at each success spot). All reuse the
    -- celebratory jingle for now (swap per-event sounds here later, config-only); burst colors
    -- differentiate them visually. =====

    -- An achievement tier completed (server: AchievementsService alongside AchievementCompleted).
    achievement_completed = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 255, 120, 220 } }, -- magenta
    },

    -- A quest was claimed (server: QuestService:Claim success).
    quest_complete = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 90, 180, 255 } }, -- sky blue
    },

    -- The daily streak reward was claimed (server: DailyService:Claim success).
    daily_claim = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 80, 220, 210 } }, -- teal
    },

    -- An escrow trade completed — fired to BOTH players (server: TradeService:_deliver).
    trade_complete = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 240, 240, 255 } }, -- white sparkle
    },

    -- Chaotic Fusion produced a new pet (server: FusionService:Fuse success).
    pet_fusion = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 185, 120, 255 } }, -- chaotic purple
    },

    -- First-ever Robux purchase bonus granted (server: MonetizationService).
    first_purchase_bonus = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 255, 160, 60 }, count = 24 }, -- big warm gold-orange
    },

    -- ===== Batch 2: combat / discovery moments =====

    -- An enemy your pets contributed to went down (server: EnemyService:_onDefeated, per
    -- contributor). FREQUENT during farming — small silent burst only; no stinger by design.
    enemy_defeated = {
        vfx = { kind = "burst", color = { 235, 90, 90 }, count = 6 },
    },

    -- A downed pet was revived by the Revive power (server: PowerService revive family).
    pet_revive = {
        sound = "power_up_stronger",
        vfx = { kind = "burst", color = { 140, 235, 140 }, count = 12 }, -- soft green comeback
    },

    -- First-ever discovery of a species/variant (server: PetIndexService — the Pet Index grew).
    new_species = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 255, 235, 120 }, count = 18 }, -- star gold
    },

    -- A hatch batch contained golden/rainbow/special reveals (server: EggService — fired ONCE per
    -- batch with the special count, not per pet).
    egg_hatch_rare = {
        sound = "celebratory_jingle",
        vfx = { kind = "burst", color = { 255, 120, 255 }, count = 24 }, -- big rainbow-pink
    },

    -- ===== Batch 3: economy / enchant / pet-down (existing toasts stay; the bus adds the juice) =====

    -- A shop item was bought (server: EconomyService — the PurchaseSuccess toast still shows).
    purchase_success = {
        vfx = { kind = "burst", color = { 255, 215, 120 }, count = 8 }, -- small gold, no stinger
    },

    -- Items sold for coins (server: EconomyService — SellSuccess toast still shows).
    sell_success = {
        vfx = { kind = "burst", color = { 150, 230, 150 }, count = 8 }, -- small green, no stinger
    },

    -- An enchant reroll SUCCEEDED (server: EnchantService — fired at the same reveal moment as
    -- EnchantPetResult so the juice syncs with the reveal).
    enchant_success = {
        sound = "cartoony_spell_cast",
        vfx = { kind = "burst", color = { 200, 120, 255 }, count = 14 }, -- arcane purple
    },

    -- One of YOUR pets went down (server: EnemyService:_downPet). Somber low thud, no burst.
    pet_down = {
        sound = "deep_earthen_impact",
    },

    -- SOURCES WIRED, NO DEFAULT REACTIONS (add a row to react — the fire is already in place):
    --   egg_hatch     — every successful hatch batch {count} (the reveal pop is animation-synced
    --                   choreography in EggHatchingService and stays there)
    --   economy_error — purchase/sell failures {message} (the error notice already informs;
    --                   add an error blip here if/when one is uploaded)
}
