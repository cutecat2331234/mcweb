<script setup lang="ts">
import { ref } from 'vue'
import { routes } from '@/lib/routes'
import { csrfHeaders } from '@/lib/csrf'
import { useDebouncedCallback } from '@/lib/useDebounce'

const props = defineProps<{
  modelValue: string
}>()

const emit = defineEmits<{
  'update:modelValue': [value: string]
}>()

type Suggestion = { insert: string; label: string; sublabel?: string | null; avatar?: string | null }
type MentionUser = { username: string; display_name?: string | null; avatar_url?: string }
type Hashtag = { name: string; slug: string }

const suggestions = ref<Suggestion[]>([])
const activeIndex = ref(0)
let mode: 'mention' | 'hashtag' | null = null

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

const schedule = useDebouncedCallback((fn: () => void) => { fn() }, 200)

async function getJson(url: string) {
  const res = await fetch(url, {
    headers: { Accept: 'application/json', ...csrfHeaders() },
    credentials: 'same-origin',
  })
  if (!res.ok) throw new Error(`Suggestion request failed with status ${res.status}`)
  return res.json()
}

async function fetchMentions(q: string) {
  try {
    const data = await getJson(`${routes.forumMentionSearch}?q=${encodeURIComponent(q)}`) as { users?: unknown }
    const users = Array.isArray(data.users)
      ? data.users.filter((user): user is MentionUser => (
          typeof user === 'object'
          && user !== null
          && typeof (user as { username?: unknown }).username === 'string'
        ))
      : []
    if (mode !== 'mention') return
    suggestions.value = users.map((user) => ({
      insert: `@${user.username} `,
      label: `@${user.username}`,
      sublabel: user.display_name,
      avatar: user.avatar_url,
    }))
    activeIndex.value = 0
  } catch {
    if (mode === 'mention') suggestions.value = []
  }
}

async function fetchHashtags(q: string) {
  try {
    const data = await getJson(`${routes.forumTagSuggest}?q=${encodeURIComponent(q)}`) as { tags?: unknown }
    const tags = Array.isArray(data.tags)
      ? data.tags.filter((tag): tag is Hashtag => (
          typeof tag === 'object'
          && tag !== null
          && typeof (tag as { name?: unknown }).name === 'string'
          && typeof (tag as { slug?: unknown }).slug === 'string'
        ))
      : []
    if (mode !== 'hashtag') return
    suggestions.value = tags.map((tag) => ({
      insert: `#${tag.slug} `,
      label: `#${tag.slug}`,
      sublabel: tag.name,
    }))
    activeIndex.value = 0
  } catch {
    if (mode === 'hashtag') suggestions.value = []
  }
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
