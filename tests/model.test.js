// node tests/model.test.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

// Model.js is a QML library: drop the pragma and load it as plain JS.
const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox)
const M = sandbox.module.exports

// Values made inside the sandbox have its prototypes; compare their JSON.
const same = (actual, expected) => assert.deepStrictEqual(JSON.parse(JSON.stringify(actual)), expected)

const savers = [
  { id: "omarchy", kind: "omarchy", installed: true, name: "Omarchy" },
  { id: "cmatrix", kind: "catalog", installed: true, name: "cmatrix" },
  { id: "pipes-sh", kind: "catalog", installed: false, name: "pipes.sh" },
  { id: "custom:clock", kind: "custom", installed: true, name: "Clock" },
]
const effects = [{ name: "beams", enabled: true }, { name: "matrix", enabled: false }]

same(M.installed(savers).map(s => s.id), ["omarchy", "cmatrix", "custom:clock"])
same(M.missing(savers).map(s => s.id), ["pipes-sh"])
same(M.catalog(savers).map(s => s.id), ["cmatrix", "pipes-sh"])
assert.strictEqual(M.find(savers, "cmatrix").name, "cmatrix")
assert.strictEqual(M.find(savers, "nope"), null)
assert.strictEqual(M.enabledCount(effects), 1)

same(M.parseKey("saver:custom:clock"), { type: "saver", id: "custom:clock" })
same(M.parseKey("more"), { type: "more", id: "" })

const closed = M.navKeys(M.installed(savers), M.catalog(savers), false, effects)
same(closed, ["saver:omarchy", "saver:cmatrix", "saver:custom:clock", "more", "effect:beams", "effect:matrix"])
const open = M.navKeys(M.installed(savers), M.catalog(savers), true, [])
same(open, ["saver:omarchy", "saver:cmatrix", "saver:custom:clock", "more", "catalog:cmatrix", "catalog:pipes-sh"])

assert.strictEqual(M.step(closed, "saver:omarchy", 1), "saver:cmatrix")
assert.strictEqual(M.step(closed, "saver:omarchy", -1), "saver:omarchy")
assert.strictEqual(M.step(closed, "effect:matrix", 1), "effect:matrix")
assert.strictEqual(M.step(closed, "gone", 1), "saver:omarchy")
assert.strictEqual(M.step([], "x", 1), "")

assert.strictEqual(M.heroMeta({ selected: "omarchy", selectedName: "Omarchy", effectsTotal: 37, effectsEnabled: 37, screensaverEnabled: true }), "Omarchy · all effects")
assert.strictEqual(M.heroMeta({ selected: "omarchy", selectedName: "Omarchy", effectsTotal: 37, effectsEnabled: 5, screensaverEnabled: true }), "Omarchy · 5 of 37 effects")
assert.strictEqual(M.heroMeta({ selected: "cmatrix", selectedName: "cmatrix", selectedAvailable: false }), "cmatrix is missing, using Omarchy")
assert.strictEqual(M.heroMeta({ selected: "cmatrix", screensaverEnabled: false }), "Turned off")
assert.ok(M.saverGlyph(savers[0]).length > 0)

assert.ok(M.isOmarchy("omarchy") && M.isOmarchy("omarchy-theme") && !M.isOmarchy("cmatrix"))
assert.strictEqual(M.heroMeta({ selected: "omarchy-theme", selectedName: "Omarchy (Theme Match)", effectsTotal: 37, effectsEnabled: 37, screensaverEnabled: true }), "Omarchy (Theme Match) · all effects")
assert.notStrictEqual(M.saverGlyph({ id: "omarchy-theme", kind: "omarchy" }), M.saverGlyph(savers[0]))

console.log("model tests passed")
