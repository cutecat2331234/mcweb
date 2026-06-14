<script setup lang="ts">
import { ref } from 'vue'
import { routes } from '@/lib/routes'

const props = defineProps<{
  modelValue: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

const suggestions = ref<Array<{ username: string }>>([])
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
}

function pick(username: string) {
  const value = props.modelValue.replace(/@([a-zA-Z0-9_]{0,32})$/, `@${username} `)
  emit('update:modelValue', value)
  suggestions.value = []
}
</script>

<template>
  <div class="relative">
    <slot :on-input="onInput" />
    <ul
      v-if="suggestions.length"
      class="absolute z-10 mt-1 max-h-40 w-full overflow-auto rounded-md border bg-background shadow"
    >
      <li
        v-for="user in suggestions"
        :key="user.username"
        class="cursor-pointer px-3 py-2 text-sm hover:bg-muted"
        @mousedown.prevent="pick(user.username)"
      >
        @{{ user.username }}
      </li>
    </ul>
  </div>
</template>
