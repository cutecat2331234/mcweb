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
const defaultAvatar = readFileSync(
  new URL('../../public/minecraft/default-skin-avatar.png', import.meta.url),
)

test('Minecraft profile visuals accept only CE local cached-skin endpoints', () => {
  const source = `${profileCard}\n${skinViewer}`

  assert.doesNotMatch(source, /crafatar|mineskin|textures\.minecraft\.net|sessionserver\.mojang\.com/i)
  assert.doesNotMatch(source, /https?:|['"`]\/\//i)
  assert.ok(profileCard.includes('^/minecraft/cached-skins/\\\\d+'))
  assert.match(profileCard, /'\/minecraft\/default-skin-avatar\.png'/)
  assert.doesNotMatch(source, /default-skin-avatar\.svg|data:image\/svg\+xml|<svg/i)
  assert.equal(defaultAvatar.subarray(0, 8).toString('hex'), '89504e470d0a1a0a')
  assert.ok(skinViewer.includes('/^\\/minecraft\\/cached-skins\\/\\d+\\/skin$/'))
})
