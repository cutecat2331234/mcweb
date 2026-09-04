import type { ObjectDirective } from 'vue'

const managedControlNameAttribute = 'data-mcweb-form-control-name'
const managedStepButtonNameAttribute = 'data-mcweb-step-button-name'

const formControlSelector = [
  'input.arco-input',
  'input.arco-input-number-input',
  'input.arco-select-view-input',
  'textarea.arco-textarea',
  'button.arco-switch',
].join(',')

const spinbuttonAriaValueAttributes = [
  'aria-valuemin',
  'aria-valuemax',
  'aria-valuenow',
] as const

function inputNumberStepDirection(button: HTMLElement, index: number) {
  if (button.closest('.arco-input-prepend')) return '−'
  if (button.closest('.arco-input-append')) return '+'
  return index === 0 ? '+' : '−'
}

export function nameArcoInputNumberStepButtons(formItem: HTMLElement, label: string) {
  formItem
    .querySelectorAll<HTMLElement>('button.arco-input-number-step-button')
    .forEach((button, index) => {
      if (button.closest('.arco-form-item') !== formItem) return

      const managed = button.getAttribute(managedStepButtonNameAttribute) === 'true'
      const hasExplicitName = button.hasAttribute('aria-label') || button.hasAttribute('aria-labelledby')
      if (!managed && hasExplicitName) return

      const direction = inputNumberStepDirection(button, index)
      button.setAttribute('aria-label', `${label} (${direction})`)
      button.setAttribute(managedStepButtonNameAttribute, 'true')
    })
}

export function repairArcoSpinbuttonAria(element: HTMLElement) {
  element.querySelectorAll<HTMLElement>('[role="spinbutton"]').forEach((spinbutton) => {
    spinbuttonAriaValueAttributes.forEach((attribute) => {
      const value = spinbutton.getAttribute(attribute)
      if (value === null) return
      if (value.trim() !== '' && Number.isFinite(Number(value))) return

      spinbutton.removeAttribute(attribute)
    })
  })
}

export function nameArcoFormControls(element: HTMLElement) {
  repairArcoSpinbuttonAria(element)

  element.querySelectorAll<HTMLElement>('.arco-form-item').forEach((formItem) => {
    const label = formItem.querySelector<HTMLElement>('.arco-form-item-label')?.textContent?.trim()
    if (!label) return

    nameArcoInputNumberStepButtons(formItem, label)

    formItem.querySelectorAll<HTMLElement>(formControlSelector).forEach((control) => {
      if (control.closest('.arco-form-item') !== formItem) return

      const managed = control.getAttribute(managedControlNameAttribute) === 'true'
      const hasExplicitName = control.hasAttribute('aria-label') || control.hasAttribute('aria-labelledby')
      if (!managed && hasExplicitName) return

      control.setAttribute('aria-label', label)
      control.setAttribute(managedControlNameAttribute, 'true')
    })
  })
}

const formControlObservers = new WeakMap<HTMLElement, MutationObserver>()

function observeArcoFormControls(element: HTMLElement) {
  nameArcoFormControls(element)
  if (typeof MutationObserver === 'undefined' || formControlObservers.has(element)) return

  const observer = new MutationObserver(() => nameArcoFormControls(element))
  observer.observe(element, {
    childList: true,
    subtree: true,
    characterData: true,
    attributes: true,
    attributeFilter: [...spinbuttonAriaValueAttributes],
  })
  formControlObservers.set(element, observer)
}

function stopObservingArcoFormControls(element: HTMLElement) {
  formControlObservers.get(element)?.disconnect()
  formControlObservers.delete(element)
}

export const vAccessibleFormControlNames: ObjectDirective<HTMLElement> = {
  mounted: observeArcoFormControls,
  updated: nameArcoFormControls,
  unmounted: stopObservingArcoFormControls,
}

export function nameArcoDialog(element: HTMLElement, name: string) {
  const dialog = element.matches('.arco-modal')
    ? element
    : element.querySelector<HTMLElement>('.arco-modal')

  if (!dialog) return

  dialog.setAttribute('role', 'dialog')
  dialog.setAttribute('aria-modal', 'true')

  const normalizedName = name.trim()
  if (normalizedName) dialog.setAttribute('aria-label', normalizedName)
}

export const vAccessibleDialog: ObjectDirective<HTMLElement, string> = {
  mounted: (element, binding) => nameArcoDialog(element, binding.value),
  updated: (element, binding) => nameArcoDialog(element, binding.value),
}
