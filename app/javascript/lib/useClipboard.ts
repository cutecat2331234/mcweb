import { onBeforeUnmount, ref } from 'vue'
import { prompt } from '@/lib/usePrompt'

export interface UseCopyToClipboardOptions {
  /** Milliseconds before `copied` flips back to false. Default 2000. */
  resetMs?: number
  /**
   * When the async clipboard write fails (e.g. insecure context / denied
   * permission), fall back to showing the prompt modal so the user can copy
   * the text manually.
   */
  fallbackPrompt?: boolean
  /** Title for the fallback prompt modal. Pass a getter for reactive i18n. */
  promptTitle?: string | (() => string)
}

/**
 * Copy-to-clipboard helper. Wraps `navigator.clipboard.writeText`, exposes a
 * `copied` flag that auto-resets, and optionally falls back to the prompt modal.
 *
 * `copy(text)` resolves to `true` on success and `false` on failure, so callers
 * that need a custom success side effect (e.g. an alert) can branch on it.
 */
export function useCopyToClipboard(options: UseCopyToClipboardOptions = {}) {
  const { resetMs = 2000, fallbackPrompt = false, promptTitle } = options
  const copied = ref(false)
  let timer: ReturnType<typeof setTimeout> | null = null

  async function copy(text: string): Promise<boolean> {
    try {
      await navigator.clipboard.writeText(text)
      copied.value = true
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => { copied.value = false }, resetMs)
      return true
    } catch {
      if (fallbackPrompt) {
        const title = typeof promptTitle === 'function' ? promptTitle() : (promptTitle ?? '')
        await prompt({ title, defaultValue: text })
      }
      return false
    }
  }

  onBeforeUnmount(() => {
    if (timer) clearTimeout(timer)
  })

  return { copied, copy }
}
