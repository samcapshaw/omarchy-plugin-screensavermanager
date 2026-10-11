.pragma library

// Pure helpers for Panel.qml, kept free of QML so tests/model.test.js can
// run them under node.

function installed(savers) {
  return (savers || []).filter(function(s) { return s && s.installed })
}

function missing(savers) {
  return (savers || []).filter(function(s) { return s && !s.installed })
}

// The known terminal screensavers from catalog.json, installed or not.
function catalog(savers) {
  return (savers || []).filter(function(s) { return s && s.kind === "catalog" })
}

function find(savers, id) {
  var list = savers || []
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === id) return list[i]
  return null
}

function enabledCount(effects) {
  return (effects || []).filter(function(e) { return e && e.enabled }).length
}

// ---- cursor keys ------------------------------------------------------------
//
// Every row the keyboard cursor can land on has a string key, so hover and
// arrow keys share one cursor and a refresh of the lists never leaves it
// pointing at a stale index.

function saverKey(id) { return "saver:" + id }
function catalogKey(id) { return "catalog:" + id }
function effectKey(name) { return "effect:" + name }

function parseKey(key) {
  var text = String(key || "")
  var colon = text.indexOf(":")
  if (colon < 0) return { type: text, id: "" }
  return { type: text.slice(0, colon), id: text.slice(colon + 1) }
}

function navKeys(installedSavers, catalogSavers, showCatalog, effects) {
  var keys = []
  ;(installedSavers || []).forEach(function(s) { keys.push(saverKey(s.id)) })
  if ((catalogSavers || []).length > 0) {
    keys.push("more")
    if (showCatalog) catalogSavers.forEach(function(s) { keys.push(catalogKey(s.id)) })
  }
  ;(effects || []).forEach(function(e) { keys.push(effectKey(e.name)) })
  return keys
}

// The key `delta` steps from `current`, clamped to the ends. A key that has
// gone (its row was removed) restarts from the top.
function step(keys, current, delta) {
  if (!keys || keys.length === 0) return ""
  var index = keys.indexOf(current)
  if (index < 0) return keys[0]
  var next = Math.max(0, Math.min(keys.length - 1, index + (delta > 0 ? 1 : delta < 0 ? -1 : 0)))
  return keys[next]
}

// ---- labels -----------------------------------------------------------------

function saverGlyph(saver) {
  if (!saver) return ""
  if (saver.kind === "omarchy") return "\u{F1104}"   // monitor-shimmer
  if (saver.kind === "custom") return "\u{F018D}"    // console
  return "\u{F07B7}"                                 // console-line
}

function heroMeta(state) {
  if (!state || !state.selected) return ""
  if (state.screensaverEnabled === false) return "Turned off"
  var name = state.selectedName || state.selected
  if (state.selected === "omarchy") {
    var total = state.effectsTotal || 0
    var on = state.effectsEnabled || 0
    return name + (on < total ? " · " + on + " of " + total + " effects" : " · all effects")
  }
  return state.selectedAvailable ? name : name + " is missing, using Omarchy"
}

// Lets node load this file for tests; QML ignores it.
if (typeof module !== "undefined") {
  module.exports = {
    installed: installed, missing: missing, catalog: catalog, find: find, enabledCount: enabledCount,
    saverKey: saverKey, catalogKey: catalogKey, effectKey: effectKey, parseKey: parseKey,
    navKeys: navKeys, step: step, saverGlyph: saverGlyph, heroMeta: heroMeta
  }
}
