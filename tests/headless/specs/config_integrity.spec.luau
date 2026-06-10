--[[
    Config integrity — [guardrail] every config must LOAD headless, and the rules that
    ConfigLoader enforces at BOOT must hold in CI.

    Why: a config that fails ConfigLoader validation is a CRITICAL STARTUP FAILURE — the whole
    server (and client) dies. Two real boot-killers shipped this way (PetSerialService DataStore
    + the enhancements bucket missing stack_size) because nothing checked configs before Studio.
    This spec is the pre-Studio gate.

    Part 1 sweeps configs/*.lua: each must require() cleanly (datatype shims in the runner cover
    Color3/UDim2/Enum-style values) and return a table.
    Part 2 ports ConfigLoader:_validateInventoryConfig's bucket rules verbatim — the exact class
    of failure that killed boot on 2026-06-09. If ConfigLoader's rules change, update BOTH (the
    error text here says so).
]]

return function()
    describe("configs/ load headless (require-time integrity)", function()
        local names = listFiles("configs")
        it("found the config directory", function()
            expect(#names > 50).to.equal(true)
        end)

        for _, file in ipairs(names) do
            local name = file:match("^(.*)%.lua$")
            if name then
                it("configs/" .. file .. " loads and returns a table", function()
                    local ok, result = pcall(loadModule, "configs/" .. file)
                    if not ok then
                        error("failed to load: " .. tostring(result))
                    end
                    expect(type(result)).to.equal("table")
                end)
            end
        end
    end)

    describe("quest MISSION CHAIN integrity (ordered, counters exist)", function()
        local quests = loadModule("configs/quests.lua")
        local stats = loadModule("configs/stats.lua")

        it("every def has a UNIQUE order (the chain is total)", function()
            local seen = {}
            for id, def in pairs(quests.defs) do
                if type(def.order) ~= "number" then
                    error("quest '" .. id .. "' has no numeric order — the chain needs one")
                end
                if seen[def.order] then
                    error(
                        "quests '"
                            .. id
                            .. "' and '"
                            .. seen[def.order]
                            .. "' share order "
                            .. def.order
                    )
                end
                seen[def.order] = id
            end
        end)

        it("every counter condition references a DECLARED stats counter", function()
            for id, def in pairs(quests.defs) do
                local c = def.condition
                if c and c.type == "counter_at_least" then
                    if not stats.counters[c.counter] then
                        error(
                            "quest '"
                                .. id
                                .. "' uses counter '"
                                .. tostring(c.counter)
                                .. "' that configs/stats.lua does not declare"
                        )
                    end
                end
            end
        end)

        it("every def has a reward and a description", function()
            for id, def in pairs(quests.defs) do
                if type(def.reward) ~= "table" then
                    error("quest '" .. id .. "' has no reward")
                end
                if type(def.description) ~= "string" then
                    error("quest '" .. id .. "' has no description")
                end
            end
        end)
    end)

    describe("inventory buckets satisfy ConfigLoader's boot rules", function()
        local cfg = loadModule("configs/inventory.lua")

        it("has the required top-level fields", function()
            for _, field in ipairs({ "version", "enabled_buckets", "buckets", "settings" }) do
                if cfg[field] == nil then
                    error("missing required field: " .. field)
                end
            end
            expect(type(cfg.version)).to.equal("string")
        end)

        it("every ENABLED bucket has a complete definition (the 2026-06-09 boot-killer)", function()
            for bucketName, enabled in pairs(cfg.enabled_buckets) do
                if enabled then
                    local bucket = cfg.buckets[bucketName]
                    if not bucket then
                        error("enabled bucket '" .. bucketName .. "' has no definition")
                    end
                    -- base fields (ConfigLoader requiredBaseFields)
                    for _, field in ipairs({ "display_name", "icon", "base_limit", "storage_type" }) do
                        if not bucket[field] then
                            error(
                                (
                                    "bucket '%s' missing required field '%s' — ConfigLoader will "
                                    .. "KILL BOOT on this (keep this spec in sync with "
                                    .. "_validateInventoryConfig)"
                                ):format(bucketName, field)
                            )
                        end
                    end
                    expect(type(bucket.display_name)).to.equal("string")
                    if type(bucket.base_limit) ~= "number" or bucket.base_limit <= 0 then
                        error("bucket '" .. bucketName .. "' base_limit must be a positive number")
                    end
                    -- per-storage-type rules
                    local st = bucket.storage_type
                    if st == "unique" or st == "stackable" then
                        if not bucket.stack_size then
                            error("bucket '" .. bucketName .. "' missing stack_size")
                        end
                        if type(bucket.item_schema) ~= "table" then
                            error("bucket '" .. bucketName .. "' item_schema must be a table")
                        end
                        if type(bucket.item_schema.required) ~= "table" then
                            error(
                                "bucket '" .. bucketName .. "' item_schema needs 'required' array"
                            )
                        end
                        if type(bucket.item_schema.optional) ~= "table" then
                            error(
                                "bucket '" .. bucketName .. "' item_schema needs 'optional' array"
                            )
                        end
                    elseif st == "mixed" then
                        if type(bucket.schema) ~= "table" then
                            error("bucket '" .. bucketName .. "' (mixed) needs a 'schema' table")
                        end
                        if
                            type(bucket.schema.stacks) ~= "table"
                            or type(bucket.schema.special) ~= "table"
                        then
                            error(
                                "bucket '"
                                    .. bucketName
                                    .. "' schema must contain 'stacks' and 'special' tables"
                            )
                        end
                    else
                        error(
                            "bucket '"
                                .. bucketName
                                .. "' storage_type must be unique/stackable/mixed (got "
                                .. tostring(st)
                                .. ")"
                        )
                    end
                end
            end
        end)
    end)
end
