import { ref } from 'vue'
import {
  applyThemePreference,
  readThemePreference,
  writeThemePreference,
} from '@/lib/themeBootstrap'

function readInitialDark(): boolean {
  if (typeof document === 'undefined') return false
  return applyThemePreference(readThemePreference()) === 'dark'
}

const isDark = ref(readInitialDark())

export function useTheme() {
  function toggleTheme() {
    const next = isDark.value ? 'light' : 'dark'
    isDark.value = writeThemePreference(next) === 'dark'
  }

  return { isDark, toggleTheme }
}
