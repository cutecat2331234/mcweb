import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'

const profileCard = readFileSync(
  new URL('../../app/javascript/components/minecraft/MinecraftProfileCard.vue', import.meta.url),
  'utf8',
)
const skinViewer = readFileSync(
  new URL('../../app/javascript/components/minecraft/MinecraftSkinViewer.vue', import.meta.url),
  'utf8',
)

test('Minecraft profile visuals accept only CE local cached-skin endpoints', () => {
  const source = `${profileCard}\n${skinViewer}`

  assert.doesNotMatch(source, /crafatar|mineskin|textures\.minecraft\.net|sessionserver\.mojang\.com/i)
  assert.doesNotMatch(source, /https?:\\?\/\\?\//i)
  assert.ok(profileCard.includes('^/minecraft/cached-skins/\\\\d+'))
  assert.match(profileCard, /default-skin-avatar\.svg/)
  assert.ok(skinViewer.includes('/^\\/minecraft\\/cached-skins\\/\\d+\\/skin$/'))
})
