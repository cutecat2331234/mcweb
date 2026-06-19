<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const open = ref(false)

const shortcuts = computed(() => [
  { keys: '?', desc: t('shortcuts.toggleHelp') },
  { keys: '/', desc: t('shortcuts.focusSearch') },
  { keys: 'Esc', desc: t('shortcuts.closeOverlay') },
  { keys: 'r', desc: t('shortcuts.replyTopic') },
  { keys: 'j / k', desc: t('shortcuts.navigatePosts') },
])

function isTypingTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false
  const tag = target.tagName
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target.isContentEditable
}

function onKeydown(event: KeyboardEvent) {
  if (isTypingTarget(event.target)) return
  if (event.key === '?' && !event.metaKey && !event.ctrlKey) {
    event.preventDefault()
    open.value = !open.value
  }
  if (event.key === 'Escape') open.value = false
}

onMounted(() => document.addEventListener('keydown', onKeydown))
onUnmounted(() => document.removeEventListener('keydown', onKeydown))

defineExpose({ open })
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
    @click.self="open = false"
  >
    <div class="w-full max-w-md rounded-lg border bg-background p-4 shadow-lg">
      <h2 class="mb-3 text-sm font-semibold">{{ t('shortcuts.title') }}</h2>
      <ul class="space-y-2 text-sm">
        <li v-for="item in shortcuts" :key="item.keys" class="flex justify-between gap-4">
          <kbd class="rounded border bg-muted px-1.5 py-0.5 font-mono text-xs">{{ item.keys }}</kbd>
          <span class="text-muted-foreground">{{ item.desc }}</span>
        </li>
      </ul>
      <p class="mt-4 text-xs text-muted-foreground">{{ t('shortcuts.hint') }}</p>
    </div>
  </div>
</template>
