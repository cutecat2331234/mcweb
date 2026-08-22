import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

export const EDITION_RANK = Object.freeze({ ce: 1, ee: 2, pvp: 3 })

const DEFAULT_DOCS_ROOT = fileURLToPath(new URL('../..', import.meta.url))

function readMarker(path) {
  const marker = JSON.parse(readFileSync(path, 'utf8'))
  const expectedRank = EDITION_RANK[marker.id]
  if (!expectedRank || marker.rank !== expectedRank) {
    throw new Error(`Invalid documentation edition marker: ${path}`)
  }
  if (!marker.label?.['zh-CN'] || !marker.label?.en) {
    throw new Error(`Edition marker requires zh-CN and en labels: ${path}`)
  }
  return marker
}

export function loadEditionMarkers(docsRoot = DEFAULT_DOCS_ROOT) {
  const root = join(docsRoot, 'editions')
  if (!existsSync(root)) throw new Error(`Missing documentation editions directory: ${root}`)

  const markers = readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
    .map((entry) => readMarker(join(root, entry.name)))
    .sort((left, right) => left.rank - right.rank)

  if (!markers.length || markers[0].id !== 'ce') {
    throw new Error('Every McWeb documentation build must inherit the CE edition marker')
  }

  markers.forEach((marker, index) => {
    if (marker.rank !== index + 1) {
      throw new Error('Edition markers must form the uninterrupted CE -> EE -> EE-PVP chain')
    }
  })

  return markers
}

export function currentEdition(docsRoot = DEFAULT_DOCS_ROOT) {
  return loadEditionMarkers(docsRoot).at(-1)
}

export function docsRootFrom(path) {
  let cursor = dirname(path)
  while (cursor !== dirname(cursor)) {
    if (existsSync(join(cursor, 'editions', 'ce.json'))) return cursor
    cursor = dirname(cursor)
  }
  throw new Error(`Could not find documentation root from ${path}`)
}
