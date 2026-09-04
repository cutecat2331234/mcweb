import assert from 'node:assert/strict'
import test from 'node:test'

import {
  nameArcoDialog,
  nameArcoFormControls,
  nameArcoInputNumberStepButtons,
  repairArcoSpinbuttonAria,
} from '../../app/javascript/directives/arcoAccessibility.ts'

function attributeStore(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial))

  return {
    getAttribute: (name: string) => values.get(name) ?? null,
    hasAttribute: (name: string) => values.has(name),
    removeAttribute: (name: string) => values.delete(name),
    setAttribute: (name: string, value: string) => values.set(name, value),
    value: (name: string) => values.get(name),
  }
}

test('Arco form controls receive the visible FormItem label as an accessible name', () => {
  const attributes = attributeStore()
  const formItem = {
    querySelector: () => ({ textContent: '  Stable mode key  ' }),
    querySelectorAll: () => [control],
  }
  const control = {
    ...attributes,
    closest: () => formItem,
  }
  const root = {
    querySelectorAll: (selector: string) => selector === '.arco-form-item' ? [formItem] : [],
  }

  nameArcoFormControls(root as unknown as HTMLElement)

  assert.equal(attributes.value('aria-label'), 'Stable mode key')
  assert.equal(attributes.value('data-mcweb-form-control-name'), 'true')
})

test('Arco form control naming preserves an explicit application-provided name', () => {
  const attributes = attributeStore({ 'aria-label': 'Search linked player' })
  const formItem = {
    querySelector: () => ({ textContent: 'Player' }),
    querySelectorAll: () => [control],
  }
  const control = {
    ...attributes,
    closest: () => formItem,
  }
  const root = {
    querySelectorAll: (selector: string) => selector === '.arco-form-item' ? [formItem] : [],
  }

  nameArcoFormControls(root as unknown as HTMLElement)

  assert.equal(attributes.value('aria-label'), 'Search linked player')
  assert.equal(attributes.value('data-mcweb-form-control-name'), undefined)
})

test('Arco input number step buttons receive distinct names from the visible field label', () => {
  const increaseAttributes = attributeStore()
  const decreaseAttributes = attributeStore()
  const formItem = {
    querySelectorAll: () => [increaseButton, decreaseButton],
  }
  const increaseButton = {
    ...increaseAttributes,
    closest: (selector: string) => selector === '.arco-form-item' ? formItem : null,
  }
  const decreaseButton = {
    ...decreaseAttributes,
    closest: (selector: string) => selector === '.arco-form-item' ? formItem : null,
  }

  nameArcoInputNumberStepButtons(formItem as unknown as HTMLElement, 'Identity ID')

  assert.equal(increaseAttributes.value('aria-label'), 'Identity ID (+)')
  assert.equal(decreaseAttributes.value('aria-label'), 'Identity ID (−)')
  assert.equal(increaseAttributes.value('data-mcweb-step-button-name'), 'true')
  assert.equal(decreaseAttributes.value('data-mcweb-step-button-name'), 'true')
})

test('Arco input number step button naming preserves an explicit application-provided name', () => {
  const attributes = attributeStore({ 'aria-label': 'Add one retry' })
  const formItem = {
    querySelectorAll: () => [button],
  }
  const button = {
    ...attributes,
    closest: (selector: string) => selector === '.arco-form-item' ? formItem : null,
  }

  nameArcoInputNumberStepButtons(formItem as unknown as HTMLElement, 'Retries')

  assert.equal(attributes.value('aria-label'), 'Add one retry')
  assert.equal(attributes.value('data-mcweb-step-button-name'), undefined)
})

test('Arco spinbuttons omit non-finite ARIA range bounds', () => {
  const attributes = attributeStore({
    'aria-valuemin': '0',
    'aria-valuemax': 'Infinity',
    'aria-valuenow': '3',
  })
  const root = {
    querySelectorAll: () => [attributes],
  }

  repairArcoSpinbuttonAria(root as unknown as HTMLElement)

  assert.equal(attributes.value('aria-valuemin'), '0')
  assert.equal(attributes.value('aria-valuemax'), undefined)
  assert.equal(attributes.value('aria-valuenow'), '3')
})

test('Arco modal content receives dialog semantics and a translated name', () => {
  const attributes = attributeStore()
  const dialog = {
    ...attributes,
  }
  const root = {
    matches: () => false,
    querySelector: () => dialog,
  }

  nameArcoDialog(root as unknown as HTMLElement, 'Reject delegation')

  assert.equal(attributes.value('role'), 'dialog')
  assert.equal(attributes.value('aria-modal'), 'true')
  assert.equal(attributes.value('aria-label'), 'Reject delegation')
})
