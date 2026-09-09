import { reactive } from 'vue'

export interface ConfirmOptions {
  title: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'default' | 'destructive'
}

interface ConfirmState {
  open: boolean
  options: ConfirmOptions
  resolve: ((value: boolean) => void) | null
}

export const confirmState = reactive<ConfirmState>({
  open: false,
  options: { title: '', message: '' },
  resolve: null,
})

export function confirm(options: ConfirmOptions): Promise<boolean> {
  // The first request also owns the interval before its lazy dialog mounts.
  // Never share its result with a different action or replace its resolver.
  if (confirmState.resolve) return Promise.resolve(false)

  return new Promise((resolve) => {
    confirmState.options = options
    confirmState.resolve = resolve
    confirmState.open = true
  })
}

export function resolveConfirm(value: boolean, expectedResolver = confirmState.resolve) {
  if (confirmState.resolve !== expectedResolver) return

  const resolve = confirmState.resolve
  confirmState.open = false
  confirmState.resolve = null
  resolve?.(value)
}
