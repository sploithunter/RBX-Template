--!strict
--[[
	Headless unit-test runner (lune).

	Runs pure-logic specs with NO Roblox Studio. Specs live in
	`tests/headless/specs/*.spec.luau` and use a TestEZ-compatible subset
	(`describe`/`it`/`expect`/`beforeEach`/`afterEach`) so the same logic can
	also be exercised by TestEZ inside Studio.

	Run:  mise exec -- lune run tests/headless/run.luau
	(or:  mise run test-headless)

	NOTE: requiring the module-under-test by relative path from a spec is wired
	up in Phase 0 when the first pure module exists. For now this proves the
	framework + reporting + exit-code loop.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local luau = require("@lune/luau")
local stdio = require("@lune/stdio")

type Result = { name: string, ok: boolean, err: string? }

local results: { Result } = {}
local contextStack: { string } = {}
local beforeStack: { { () -> () } } = {}

local function fullName(name: string): string
    local parts = table.clone(contextStack)
    table.insert(parts, name)
    return table.concat(parts, " › ")
end

-- ---- matchers ----------------------------------------------------------
local function makeMatchers(value: any, negated: boolean)
    local function check(pass: boolean, message: string)
        if negated then
            pass = not pass
        end
        if not pass then
            error(message, 3)
        end
    end

    local to = {}
    to.equal = function(expected: any)
        check(value == expected, `expected {tostring(value)} to equal {tostring(expected)}`)
    end
    to.ok = function()
        check(value ~= nil, `expected value to be ok (non-nil), got {tostring(value)}`)
    end
    to.near = function(expected: number, limit: number?)
        local lim = limit or 1e-7
        check(
            type(value) == "number" and math.abs(value - expected) <= lim,
            `expected {tostring(value)} to be near {tostring(expected)} (±{lim})`
        )
    end
    to.a = function(typeName: string)
        check(
            type(value) == typeName,
            `expected {tostring(value)} to be a {typeName}, got {type(value)}`
        )
    end
    -- TestEZ-style `.to.be.<matcher>` alias
    to.be = { ok = to.ok, near = to.near, a = to.a, equal = to.equal }
    return to
end

local function expect(value: any)
    return {
        to = makeMatchers(value, false),
        never = { to = makeMatchers(value, true) },
    }
end

-- ---- structure ---------------------------------------------------------
local function describe(name: string, fn: () -> ())
    table.insert(contextStack, name)
    table.insert(beforeStack, {})
    fn()
    table.remove(beforeStack)
    table.remove(contextStack)
end

local function beforeEach(fn: () -> ())
    local top = beforeStack[#beforeStack]
    if top then
        table.insert(top, fn)
    end
end

local function it(name: string, fn: () -> ())
    for _, hooks in beforeStack do
        for _, hook in hooks do
            hook()
        end
    end
    local ok, err = pcall(fn)
    table.insert(
        results,
        { name = fullName(name), ok = ok, err = if ok then nil else tostring(err) }
    )
end

-- ---- discover + load specs --------------------------------------------
local SPEC_DIR = "tests/headless/specs"

local env = {
    describe = describe,
    it = it,
    expect = expect,
    beforeEach = beforeEach,
    afterEach = function(_: () -> ()) end, -- no-op subset for now
}

local specFiles: { string } = {}
if fs.isDir(SPEC_DIR) then
    for _, entry in fs.readDir(SPEC_DIR) do
        if string.match(entry, "%.spec%.luau$") then
            table.insert(specFiles, `{SPEC_DIR}/{entry}`)
        end
    end
end
table.sort(specFiles)

for _, path in specFiles do
    local source = fs.readFile(path)
    local chunk = luau.load(source, { debugName = path, environment = env })
    local exported = chunk()
    if type(exported) == "function" then
        exported()
    end
end

-- ---- report ------------------------------------------------------------
local passed, failed = 0, 0
for _, r in results do
    if r.ok then
        passed += 1
    else
        failed += 1
    end
end

print(string.rep("=", 56))
print("🧪 HEADLESS TEST RESULTS")
print(string.rep("=", 56))
for _, r in results do
    if r.ok then
        stdio.write(`  ✓ {r.name}\n`)
    else
        stdio.write(`  ✗ {r.name}\n      {r.err}\n`)
    end
end
print(string.rep("-", 56))
print(`Total: {#results} | Passed: {passed} | Failed: {failed} | Specs: {#specFiles}`)
print(string.rep("=", 56))

if failed > 0 then
    process.exit(1)
end
