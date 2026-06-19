import { reactive } from 'vue'

export interface PromptOptions {
  title: string
  message?: string
  defaultValue?: string
  placeholder?: string
  confirmLabel?: string
  cancelLabel?: string
}

interface PromptState {
  open: boolean
  value: string
  options: PromptOptions
  resolve: ((value: string | null) => void) | null
}

export const promptState = reactive<PromptState>({
  open: false,
  value: '',
  options: { title: '' },
  resolve: null,
})

export function prompt(options: PromptOptions): Promise<string | null> {
  return new Promise((resolve) => {
    promptState.options = options
    promptState.value = options.defaultValue || ''
    promptState.resolve = resolve
    promptState.open = true
  })
}

export function resolvePrompt(value: string | null) {
  promptState.resolve?.(value)
  promptState.open = false
  promptState.resolve = null
}
