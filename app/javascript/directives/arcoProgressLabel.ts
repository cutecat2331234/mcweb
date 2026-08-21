import type { ObjectDirective } from 'vue'

function progressbarFor(element: HTMLElement) {
  return element.matches('[role="progressbar"]')
    ? element
    : element.querySelector<HTMLElement>('[role="progressbar"]')
}

export function labelArcoProgress(element: HTMLElement, label: string) {
  const progressbar = progressbarFor(element)
  if (!progressbar) return

  const normalizedLabel = label.trim()
  if (normalizedLabel) {
    progressbar.setAttribute('aria-label', normalizedLabel)
  } else {
    progressbar.removeAttribute('aria-label')
  }
}

export const vArcoProgressLabel: ObjectDirective<HTMLElement, string> = {
  mounted: (element, binding) => labelArcoProgress(element, binding.value),
  updated: (element, binding) => labelArcoProgress(element, binding.value),
}
