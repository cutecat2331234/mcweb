import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { currentEdition, loadEditionMarkers } from '../scripts/lib/edition.mjs'

function marker(root, id, rank, directories = [id]) {
  mkdirSync(join(root, 'editions'), { recursive: true })
  writeFileSync(join(root, 'editions', `${id}.json`), JSON.stringify({
    id,
    rank,
    label: { 'zh-CN': id, en: id },
    sections: directories.map((directory) => ({
      directory,
      label: { 'zh-CN': directory, en: directory },
    })),
  }))
}

test('CE is the required root edition', () => {
  const root = mkdtempSync(join(tmpdir(), 'mcweb-docs-edition-'))
  marker(root, 'ce', 1)
  assert.equal(currentEdition(root).id, 'ce')
})

test('downstream markers must form an uninterrupted chain', () => {
  const root = mkdtempSync(join(tmpdir(), 'mcweb-docs-edition-'))
  marker(root, 'ce', 1)
  marker(root, 'pvp', 3)
  assert.throws(() => loadEditionMarkers(root), /uninterrupted/)
})

test('highest inherited marker selects the current edition', () => {
  const root = mkdtempSync(join(tmpdir(), 'mcweb-docs-edition-'))
  marker(root, 'ce', 1)
  marker(root, 'ee', 2)
  assert.equal(currentEdition(root).id, 'ee')
})

test('edition markers own unique additive sidebar sections', () => {
  const root = mkdtempSync(join(tmpdir(), 'mcweb-docs-edition-'))
  marker(root, 'ce', 1, ['getting-started'])
  marker(root, 'ee', 2, ['enterprise'])

  const directories = loadEditionMarkers(root)
    .flatMap((edition) => edition.sections.map((section) => section.directory))
  assert.deepEqual(directories, ['getting-started', 'enterprise'])
})

test('duplicate section ownership fails closed', () => {
  const root = mkdtempSync(join(tmpdir(), 'mcweb-docs-edition-'))
  marker(root, 'ce', 1, ['shared'])
  marker(root, 'ee', 2, ['shared'])

  assert.throws(() => loadEditionMarkers(root), /unique/)
})
