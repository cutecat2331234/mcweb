<script setup lang="ts">
import { ref } from 'vue'
import { routes } from '@/lib/routes'

const props = defineProps<{
  modelValue: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

type Suggestion = { insert: string; label: string; sublabel?: string | null; avatar?: string | null }

const suggestions = ref<Suggestion[]>([])
const activeIndex = ref(0)
let mode: 'mention' | 'hashtag' | null = null
let debounceTimer: ReturnType<typeof setTimeout> | null = null

const MENTION_RE = /@([a-zA-Z0-9_]{0,32})$/
const HASHTAG_RE = /#([a-zA-Z0-9_-]{0,32})$/

function onInput(event: Event) {
  const value = (event.target as HTMLTextAreaElement).value
  emit('update:modelValue', value)

  const mention = value.match(MENTION_RE)
  const hashtag = value.match(HASHTAG_RE)

  if (mention && mention[1].length >= 2) {
    mode = 'mention'
    schedule(() => fetchMentions(mention[1]))
  } else if (hashtag && hashtag[1].length >= 1) {
    mode = 'hashtag'
    schedule(() => fetchHashtags(hashtag[1]))
  } else {
    suggestions.value = []
    mode = null
  }
}

function schedule(fn: () => void) {
  if (debounceTimer) clearTimeout(debounceTimer)
  debounceTimer = setTimeout(fn, 200)
}

async function getJson(url: string) {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
  const res = await fetch(url, {
    headers: { Accept: 'application/json', 'X-CSRF-Token': token || '' },
    credentials: 'same-origin',
  })
  return res.json()
}

async function fetchMentions(q: string) {
  const data = await getJson(`${routes.forumMentionSearch}?q=${encodeURIComponent(q)}`)
  suggestions.value = (data.users || []).map((u: { username: string; display_name?: string | null; avatar_url?: string }) => ({
    insert: `@${u.username} `,
    label: `@${u.username}`,
    sublabel: u.display_name,
    avatar: u.avatar_url,
  }))
  activeIndex.value = 0
}

async function fetchHashtags(q: string) {
  const data = await getJson(`${routes.forumTagSuggest}?q=${encodeURIComponent(q)}`)
  suggestions.value = (data.tags || []).map((t: { name: string; slug: string }) => ({
    insert: `#${t.slug} `,
    label: `#${t.slug}`,
    sublabel: t.name,
  }))
  activeIndex.value = 0
}

function pick(suggestion: Suggestion) {
  const re = mode === 'hashtag' ? HASHTAG_RE : MENTION_RE
  const value = props.modelValue.replace(re, suggestion.insert)
  emit('update:modelValue', value)
  suggestions.value = []
  mode = null
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
      pick(chosen)
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
        v-for="(s, index) in suggestions"
        :key="s.insert"
        class="flex cursor-pointer items-center gap-2 px-3 py-2 text-sm hover:bg-muted"
        :class="index === activeIndex ? 'bg-muted' : ''"
        @mousedown.prevent="pick(s)"
      >
        <img v-if="s.avatar" :src="s.avatar" :alt="s.label" class="h-6 w-6 rounded-full" />
        <span class="font-medium">{{ s.label }}</span>
        <span v-if="s.sublabel" class="text-muted-foreground">{{ s.sublabel }}</span>
      </li>
    </ul>
  </div>
</template>
