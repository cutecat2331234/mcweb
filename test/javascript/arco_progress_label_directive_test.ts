import assert from 'node:assert/strict'
import test from 'node:test'

import { labelArcoProgress } from '../../app/javascript/directives/arcoProgressLabel.ts'

function attributeStore(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial))

  return {
    getAttribute: (name: string) => values.get(name) ?? null,
    removeAttribute: (name: string) => values.delete(name),
    setAttribute: (name: string, value: string) => values.set(name, value),
  }
}

test('Arco progress receives its accessible name on a descendant progressbar', () => {
  const progressbar = attributeStore()
  const root = {
    matches: () => false,
    querySelector: (selector: string) => selector === '[role="progressbar"]' ? progressbar : null,
  }

  labelArcoProgress(root as unknown as HTMLElement, '  Testing progress  ')

  assert.equal(progressbar.getAttribute('aria-label'), 'Testing progress')
})

test('Arco progress supports a component root that is itself the progressbar', () => {
  const attributes = attributeStore()
  const root = {
    ...attributes,
    matches: (selector: string) => selector === '[role="progressbar"]',
    querySelector: () => null,
  }

  labelArcoProgress(root as unknown as HTMLElement, 'Queue completion')

  assert.equal(attributes.getAttribute('aria-label'), 'Queue completion')
})

test('Arco progress removes its managed accessible name when the label is empty', () => {
  const progressbar = attributeStore({ 'aria-label': 'Previous progress' })
  const root = {
    matches: () => false,
    querySelector: () => progressbar,
  }

  labelArcoProgress(root as unknown as HTMLElement, '   ')

  assert.equal(progressbar.getAttribute('aria-label'), null)
})
