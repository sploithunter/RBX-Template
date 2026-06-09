--[[
    GameEvents config integrity — [unit] guardrail for configs/game_events.lua.
    Run: mise run test-headless

    The dispatcher (src/Client/Systems/GameEvents.lua) is instance-heavy (Sounds/VFX), so it can't
    run headless — but the CONFIG is pure data. This pins the contract so a typo (unknown reaction
    kind, or a `sound` pointing at a missing sounds.lua key) fails the gate instead of going silent
    in-game.
]]

local gameEvents = loadModule("configs/game_events.lua")
local sounds = loadModule("configs/sounds.lua")

-- Reaction kinds the dispatcher knows how to apply. Keep in sync with GameEvents REACTIONS.
local KNOWN_KINDS = {
    sound = true,
    vfx = true,
}

return function()
    describe("game_events config", function()
        it("is a table of event -> reactions tables", function()
            expect(type(gameEvents)).to.equal("table")
            for name, entry in pairs(gameEvents) do
                expect(type(name)).to.equal("string")
                expect(type(entry)).to.equal("table")
            end
        end)

        it("only uses reaction kinds the dispatcher implements", function()
            for name, entry in pairs(gameEvents) do
                for kind in pairs(entry) do
                    if not KNOWN_KINDS[kind] then
                        error(
                            ("event '%s' uses unknown reaction kind '%s'"):format(
                                name,
                                tostring(kind)
                            )
                        )
                    end
                end
            end
        end)

        it("every `sound` reaction points at a real sounds.lua entry with an id", function()
            for name, entry in pairs(gameEvents) do
                local key = entry.sound
                if key ~= nil then
                    expect(type(key)).to.equal("string")
                    local def = sounds[key]
                    if not (type(def) == "table" and def.id) then
                        error(
                            ("event '%s' sound '%s' has no sounds.lua entry with an id"):format(
                                name,
                                tostring(key)
                            )
                        )
                    end
                end
            end
        end)

        it("level_up is wired (the migrated example stays intact)", function()
            expect(type(gameEvents.level_up)).to.equal("table")
            expect(gameEvents.level_up.sound).to.equal("celebratory_jingle")
        end)
    end)
end
