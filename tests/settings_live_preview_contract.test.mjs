import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const testDir = path.dirname(fileURLToPath(import.meta.url))
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n')

const uiSource = read('ui', 'app.js')
const cssSource = read('ui', 'style.css')
const luaSource = read('imports', 'settings', 'client.lua')

const clampFunction = uiSource.match(/function clamp\(n, min, max\) \{[\s\S]*?\n\}/)
const settingsScaleFunction = uiSource.match(/function getSettingsUiScale\(\) \{[\s\S]*?\n\}/)
assert.ok(clampFunction, 'shared UI scale clamp must remain discoverable')
assert.ok(settingsScaleFunction, 'settings resolution scale must remain discoverable')

const evaluateSettingsScale = Function(
  'window',
  `${clampFunction[0]}\n${settingsScaleFunction[0]}\nreturn getSettingsUiScale()`,
)

assert.equal(evaluateSettingsScale({ innerHeight: 720 }), 0.86, '720p keeps a readable compact floor')
assert.equal(evaluateSettingsScale({ innerHeight: 1080 }), 1, '1080p is the base settings scale')
assert.equal(evaluateSettingsScale({ innerHeight: 1440 }), 1440 / 1080, '1440p scales above the 1080p base')
assert.equal(evaluateSettingsScale({ innerHeight: 2160 }), 2, '4K reaches the 2x settings scale')
assert.equal(evaluateSettingsScale({ innerHeight: 4320 }), 2, 'settings scale remains bounded above 4K')

const handleChangeMatch = uiSource.match(
  /const handleChange = useCallback\(\(tabId, key, value\) => \{([\s\S]*?)\n    \}, \[[^\]]*session[^\]]*\]\)/,
)
assert.ok(handleChangeMatch, 'SettingsPanel handleChange must remain discoverable')
assert.match(
  handleChangeMatch[1],
  /nuiPost\('settingsPreview', \{ tabId, key, value, session \}\)/,
  'every field edit must cross the NUI boundary immediately',
)
assert.match(handleChangeMatch[1], /response\?\.ok === true[\s\S]*?sessionRef\.current !== normalizeSession\(session\)/)
assert.match(handleChangeMatch[1], /Object\.is\(currentTabValues\[key\], value\)[\s\S]*?rollbackTabValues/)
assert.match(
  uiSource,
  /const handleReset = useCallback[\s\S]*?prev\[tab\.id\] === nextValues[\s\S]*?PREVIEW FAILED/,
  'a rejected reset preview must roll back only the still-current optimistic reset',
)
assert.match(uiSource, /settingsAction'[\s\S]*?ACTION FAILED/)
assert.match(uiSource, /settingsPreviewSound'[\s\S]*?PREVIEW FAILED/)

const previewCallback = luaSource.match(
  /RegisterNUICallback\('settingsPreview', function\(data, cb\)([\s\S]*?)\nend\)/,
)
assert.ok(previewCallback, 'Lua must handle settingsPreview')
assert.match(previewCallback[1], /cb\(\{ ok =/, 'settingsPreview must acknowledge its NUI callback')
assert.match(previewCallback[1], /previewTabValue\(tabId, key, value\)/)

const cancelCallback = luaSource.match(
  /RegisterNUICallback\('settingsCancel', function\(data, cb\)([\s\S]*?)\nend\)/,
)
assert.ok(cancelCallback, 'settingsCancel must remain registered')
assert.match(cancelCallback[1], /matchesSettingsModal\(data\)/, 'Cancel must reject a stale session')
assert.match(cancelCallback[1], /rollbackPreviewValues\(\)/, 'Cancel must restore the pre-open values')

const saveCallback = luaSource.match(
  /RegisterNUICallback\('settingsSave', function\(data, cb\)([\s\S]*?)\nend\)/,
)
assert.ok(saveCallback, 'settingsSave must remain registered')
assert.match(saveCallback[1], /commitPreviewValues\(/, 'Save must persist previewed values')
assert.match(uiSource, /response\?\.ok === true/, 'the panel must stay open when Save or Cancel fails')
assert.match(
  uiSource,
  /React\.createElement\(InteractionSurface, \{ hidden: settingsPanel\.open \}\)/,
  'interaction prompts must not render over the modal settings surface',
)
assert.match(
  uiSource,
  /function InteractionSurface\([\s\S]*?if \(hidden\) return null;/,
  'the isolated interaction surface must honor the settings modal visibility gate',
)

const panelBlock = cssSource.match(/\.cortex-settings-panel \{([\s\S]*?)\n\}/)
assert.ok(panelBlock, 'settings panel CSS must remain discoverable')

const widthMatch = panelBlock[1].match(/width:\s*min\(calc\((\d+)px \* var\(--cortex-settings-scale\)\)/)
const heightMatch = panelBlock[1].match(/height:\s*min\(calc\((\d+)px \* var\(--cortex-settings-scale\)\)/)
assert.ok(widthMatch, 'settings panel must use a compact 1080p base width')
assert.ok(heightMatch, 'settings panel must use a compact 1080p base height')
assert.ok(Number(widthMatch[1]) <= 640, 'settings panel 1080p base width must be 640px or less')
assert.ok(Number(heightMatch[1]) <= 680, 'settings panel 1080p base height must be 680px or less')

console.log('settings live preview contract: PASS')
