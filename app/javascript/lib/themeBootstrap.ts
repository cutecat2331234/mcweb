export const THEME_STORAGE_KEY = 'mc-theme'
export type ThemePreference = 'light' | 'dark' | 'system'

export function normalizeThemePreference(value: unknown): ThemePreference {
  return value === 'light' || value === 'dark' || value === 'system' ? value : 'system'
}

export function readThemePreference(): ThemePreference {
  if (typeof window === 'undefined') return 'system'
  try {
    return normalizeThemePreference(window.localStorage.getItem(THEME_STORAGE_KEY))
  } catch {
    return 'system'
  }
}

export function resolvedTheme(preference = readThemePreference()): 'light' | 'dark' {
  if (preference === 'light' || preference === 'dark') return preference
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

export function applyThemePreference(preference = readThemePreference()): 'light' | 'dark' {
  const theme = resolvedTheme(preference)
  document.documentElement.classList.toggle('dark', theme === 'dark')
  document.documentElement.dataset.theme = theme
  document.documentElement.style.colorScheme = theme
  return theme
}

export function writeThemePreference(preference: ThemePreference): 'light' | 'dark' {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, preference)
  } catch {
    // Storage can be disabled; the current document still receives the theme.
  }
  return applyThemePreference(preference)
}
