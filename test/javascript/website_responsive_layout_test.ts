import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import test from 'node:test'

const websiteCss = readFileSync(
  resolve(process.cwd(), 'app/javascript/styles/website.css'),
  'utf8',
)

test('mobile feature and CTA overrides follow their base website rules', () => {
  const featureCardBase = websiteCss.indexOf('.feature-card {')
  const featureGlyphBase = websiteCss.indexOf('.feature-glyph {')
  const ctaBandBase = websiteCss.indexOf('.cta-band {')
  const mobileStart = websiteCss.indexOf('@media (max-width: 767px)')
  const mobileEnd = websiteCss.indexOf('.cta-aura', mobileStart)

  assert.notEqual(featureCardBase, -1)
  assert.notEqual(featureGlyphBase, -1)
  assert.notEqual(ctaBandBase, -1)
  assert.ok(mobileStart > featureCardBase)
  assert.ok(mobileStart > featureGlyphBase)
  assert.ok(mobileStart > ctaBandBase)
  assert.ok(mobileEnd > mobileStart)

  const mobileRules = websiteCss.slice(mobileStart, mobileEnd)
  assert.match(
    mobileRules,
    /\.feature-card\s*\{[\s\S]*?align-items:\s*flex-start;[\s\S]*?flex-direction:\s*column;[\s\S]*?gap:\s*1rem;[\s\S]*?padding:\s*1\.25rem;/,
  )
  assert.match(
    mobileRules,
    /\.feature-glyph\s*\{[\s\S]*?width:\s*3\.5rem;[\s\S]*?height:\s*3\.5rem;/,
  )
  assert.match(mobileRules, /\.cta-band\s*\{[\s\S]*?padding:\s*2\.5rem 1\.25rem;/)
})
