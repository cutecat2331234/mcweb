import { ref } from 'vue'

const isDark = ref(
  typeof document !== 'undefined' && document.documentElement.classList.contains('dark'),
)

export function useTheme() {
  function toggleTheme() {
    const next = isDark.value ? 'light' : 'dark'
    document.documentElement.classList.toggle('dark', next === 'dark')
    localStorage.setItem('mc-theme', next)
    isDark.value = next === 'dark'
  }

  return { isDark, toggleTheme }
}
