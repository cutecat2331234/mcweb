<script setup lang="ts">
import { ref } from 'vue'
import { routes } from '@/lib/routes'

const props = defineProps<{
  modelValue: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const suggestions = ref<Array<{ username: string; display_name?: string | null; avatar_url?: string }>>([])
const activeIndex = ref(0)
let debounceTimer: ReturnType<typeof setTimeout> | null = null

function onInput(event: Event) {
  const value = (event.target as HTMLTextAreaElement).value
  emit('update:modelValue', value)

  const match = value.match(/@([a-zA-Z0-9_]{0,32})$/)
  if (!match || match[1].length < 2) {
    suggestions.value = []
    return
  }

  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => fetchSuggestions(match[1]), 200)
}

async function fetchSuggestions(q: string) {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
  const res = await fetch(`${routes.forumMentionSearch}?q=${encodeURIComponent(q)}`, {
    headers: { Accept: 'application/json', 'X-CSRF-Token': token || '' },
    credentials: 'same-origin',
  })
  const data = await res.json()
  suggestions.value = data.users || []
  activeIndex.value = 0
}

function pick(username: string) {
  const value = props.modelValue.replace(/@([a-zA-Z0-9_]{0,32})$/, `@${username} `)
  emit('update:modelValue', value)
  suggestions.value = []
}

function onKeydown(event: KeyboardEvent) {
  if (!suggestions.value.length) return
  const count = suggestions.value.length
  if (event.key === 'ArrowDown') {
    event.preventDefault()
    activeIndex.value = (activeIndex.value + 1) % count
  } else if (event.key === 'ArrowUp') {
    event.preventDefault()
    activeIndex.value = (activeIndex.value - 1 + count) % count
  } else if (event.key === 'Enter' || event.key === 'Tab') {
    const chosen = suggestions.value[activeIndex.value]
    if (chosen) {
      event.preventDefault()
      pick(chosen.username)
    }
  } else if (event.key === 'Escape') {
    suggestions.value = []
  }
}
</script>

<template>
  <div class="relative">
    <slot :on-input="onInput" :on-keydown="onKeydown" />
    <ul
      v-if="suggestions.length"
      class="absolute z-10 mt-1 max-h-48 w-full overflow-auto rounded-md border bg-background shadow"
    >
      <li
        v-for="(user, index) in suggestions"
        :key="user.username"
        class="flex cursor-pointer items-center gap-2 px-3 py-2 text-sm hover:bg-muted"
        :class="index === activeIndex ? 'bg-muted' : ''"
        @mousedown.prevent="pick(user.username)"
      >
        <img v-if="user.avatar_url" :src="user.avatar_url" :alt="user.username" class="h-6 w-6 rounded-full" />
        <span class="font-medium">@{{ user.username }}</span>
        <span v-if="user.display_name" class="text-muted-foreground">{{ user.display_name }}</span>
      </li>
    </ul>
  </div>
</template>
