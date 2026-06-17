import { ref } from 'vue'

function readInitialDark(): boolean {
  if (typeof document === 'undefined') return false
  const stored = localStorage.getItem('mc-theme')
  if (stored === 'dark') return true
  if (stored === 'light') return false
  return document.documentElement.classList.contains('dark')
}

const isDark = ref(readInitialDark())

export function useTheme() {
  function toggleTheme() {
    const next = isDark.value ? 'light' : 'dark'
    document.documentElement.classList.toggle('dark', next === 'dark')
    localStorage.setItem('mc-theme', next)
    isDark.value = next === 'dark'
  }

  return { isDark, toggleTheme }
}
