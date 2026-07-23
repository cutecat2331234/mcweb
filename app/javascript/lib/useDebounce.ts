import { onBeforeUnmount } from 'vue'

export interface DebouncedCallback<T extends (...args: never[]) => unknown> {
  (...args: Parameters<T>): void
  /** Cancel any pending invocation. Also runs automatically on unmount. */
  cancel: () => void
}

/**
 * Returns a debounced wrapper around `fn`: repeated calls within `delay` ms
 * reset the timer, so only the trailing call runs. The pending timer is cleared
 * automatically on component unmount.
 */
export function useDebouncedCallback<T extends (...args: never[]) => unknown>(
  fn: T,
  delay: number,
): DebouncedCallback<T> {
  let timer: ReturnType<typeof setTimeout> | null = null

  const debounced = ((...args: Parameters<T>) => {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => {
      timer = null
      fn(...args)
    }, delay)
  }) as DebouncedCallback<T>

  debounced.cancel = () => {
    if (timer) {
      clearTimeout(timer)
      timer = null
    }
  }

  onBeforeUnmount(debounced.cancel)

  return debounced
}
