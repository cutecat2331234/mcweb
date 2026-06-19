<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref, watch, computed, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import BulkModerateToolbar from '@/components/portal/BulkModerateToolbar.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/useConfirm'
import { prompt } from '@/lib/usePrompt'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export type SearchTopic = TopicListItem

export interface SearchPost {
  id: number
  body: string
  body_html?: string | null
  author: string
  topic_title: string
  topic_url: string
  created_at: string
}

export interface SectionOption {
  slug: string
  name: string
  category: string | null
}

const props = defineProps<{
  query: string
  section: string | null
  category?: string
  author: string
  tag: string
  solved: string
  locked?: string
  pinned?: string
  wiki?: string
  featured?: string
  poll?: string
  noreplies?: string
  titleOnly?: boolean
  postsOnly?: boolean
  assigned?: string
  mine?: string
  scope?: string
  createdAfter?: string
  createdBefore?: string
  topicSort?: string
  postSort?: string
  sections: SectionOption[]
  categories?: Array<{ slug: string; name: string }>
  tags: Array<{ slug: string; name: string }>
  topics: SearchTopic[]
  posts: SearchPost[]
  topicsPagination: PaginationMeta
  postsPagination: PaginationMeta
  savedSearches?: Array<{
    id: number
    name: string
    query: string
    url: string
    rss_url?: string
    filter_labels?: string[]
    update_url?: string
    delete_url: string
    notify_daily?: boolean
    notify_in_app?: boolean
    webhook_url?: string | null
  }>
  loggedIn?: boolean
  forumStaff?: boolean
  canBulkModerate?: boolean
  bulkModerateUrl?: string | null
  saveSearchUrl?: string | null
  savedSearchLimit?: number | null
  savedSearchCount?: number
  savedSearchesOpmlUrl?: string | null
  suggestUrl?: string | null
  searchRssUrl?: string | null
  searchOpmlUrl?: string | null
  searchHistories?: Array<{
    id: number
    query: string
    filter_labels?: string[]
    url: string
    delete_url: string
    searched_at: string
  }>
  clearSearchHistoryUrl?: string | null
  searchHistoriesOpmlUrl?: string | null
  searchFeedsOpmlUrl?: string | null
  excludeTerms?: string[]
  activeFilters?: Array<{ param: string; label: string; value?: string | null }>
}>()

const atSavedSearchLimit = computed(() => {
  if (!props.savedSearchLimit) return false
  return (props.savedSearchCount ?? 0) >= props.savedSearchLimit
})

const q = ref(props.query)
const sectionSlug = ref(props.section || '')
const categorySlug = ref(props.category || '')
const author = ref(props.author)
const tagSlug = ref(props.tag)
const solved = ref(props.solved)
const locked = ref(props.locked || '')
const pinned = ref(props.pinned || '')
const wiki = ref(props.wiki || '')
const featured = ref(props.featured || '')
const poll = ref(props.poll || '')
const noreplies = ref(props.noreplies || '')
const titleOnly = ref(!!props.titleOnly)
const postsOnly = ref(!!props.postsOnly)
const assigned = ref(props.assigned || '')
const mine = ref(props.mine || '')
const scope = ref(props.scope || '')
const createdAfter = ref(props.createdAfter || '')
const createdBefore = ref(props.createdBefore || '')
const topicSort = ref(props.topicSort || 'recent')
const postSort = ref(props.postSort || 'recent')
const showAdvanced = ref(
  !!(props.locked || props.pinned || props.wiki || props.featured || props.poll ||
    props.noreplies || props.assigned || props.mine || props.scope || props.category)
)
const saveName = ref('')
const saveNotifyDaily = ref(false)
const saveWebhookUrl = ref('')
const selectedTopicIds = ref<string[]>([])

function bulkModerate(action: string) {
  if (!props.bulkModerateUrl || selectedTopicIds.value.length === 0) return
  router.patch(props.bulkModerateUrl, {
    topic_ids: selectedTopicIds.value,
    action_type: action,
    return_to: window.location.pathname + window.location.search,
  }, {
    onSuccess: () => { selectedTopicIds.value = [] },
  })
}
const saving = ref(false)
const saveError = ref('')
const shareCopied = ref(false)

const sectionSelectOptions = computed(() => [
  { value: '', label: t('forum.search.allSections') },
  ...props.sections.map((sec) => ({
    value: sec.slug,
    label: `${sec.category ? `${sec.category} / ` : ''}${sec.name}`,
  })),
])

const tagSelectOptions = computed(() => [
  { value: '', label: t('forum.search.allTags') },
  ...props.tags.map((tag) => ({ value: tag.slug, label: `#${tag.name}` })),
])

const solvedOptions = computed(() => [
  { value: '', label: t('forum.search.allStatus') },
  { value: 'unsolved', label: t('forum.search.unsolved') },
  { value: 'solved', label: t('forum.search.solved') },
])

const topicSortOptions = computed(() => [
  { value: 'recent', label: t('forum.search.topicSortRecent') },
  { value: 'oldest', label: t('forum.search.topicSortOldest') },
])

const postSortOptions = computed(() => [
  { value: 'recent', label: t('forum.search.postSortRecent') },
  { value: 'oldest', label: t('forum.search.postSortOldest') },
])

const categorySelectOptions = computed(() => [
  { value: '', label: t('forum.search.allCategories') },
  ...(props.categories || []).map((cat) => ({ value: cat.slug, label: cat.name })),
])

const lockedOptions = computed(() => [
  { value: '', label: t('forum.search.lockStatus') },
  { value: 'locked', label: t('forum.search.locked') },
  { value: 'unlocked', label: t('forum.search.unlocked') },
])

const pinnedOptions = computed(() => [
  { value: '', label: t('forum.search.pinStatus') },
  { value: 'pinned', label: t('forum.search.pinned') },
  { value: 'unpinned', label: t('forum.search.unpinned') },
])

const wikiOptions = computed(() => [
  { value: '', label: 'Wiki' },
  { value: 'wiki', label: t('forum.search.wikiTopics') },
  { value: 'nonwiki', label: t('forum.search.nonWiki') },
])

const featuredOptions = computed(() => [
  { value: '', label: t('forum.search.featured') },
  { value: 'featured', label: t('forum.search.featuredTopics') },
])

const pollOptions = computed(() => [
  { value: '', label: t('forum.search.poll') },
  { value: 'poll', label: t('forum.search.hasPoll') },
])

const norepliesOptions = computed(() => [
  { value: '', label: t('forum.search.replies') },
  { value: 'noreplies', label: t('forum.search.noReplies') },
])

const assignedOptions = computed(() => [
  { value: '', label: t('forum.search.assignment') },
  { value: 'assigned', label: t('forum.search.assigned') },
  { value: 'unassigned', label: t('forum.search.unassigned') },
])

const mineOptions = computed(() => [
  { value: '', label: t('forum.search.scope') },
  { value: 'mine', label: t('forum.search.myTopics') },
])

const scopeOptions = computed(() => [
  { value: '', label: t('forum.search.subscription') },
  { value: 'bookmarks', label: t('forum.search.myBookmarks') },
  { value: 'watching', label: t('forum.search.watching') },
  { value: 'unread', label: t('forum.search.unread') },
])

watch(titleOnly, (value) => {
  if (value) postsOnly.value = false
})
watch(postsOnly, (value) => {
  if (value) titleOnly.value = false
})

type SuggestItem = { title?: string; name?: string; username?: string; category?: string | null; url: string }
const suggestOpen = ref(false)
const suggestLoading = ref(false)
const suggestTopics = ref<SuggestItem[]>([])
const suggestTags = ref<SuggestItem[]>([])
const suggestUsers = ref<SuggestItem[]>([])
const suggestSections = ref<SuggestItem[]>([])
const suggestSavedSearches = ref<SuggestItem[]>([])
const suggestActiveIndex = ref(-1)
let suggestTimer: ReturnType<typeof setTimeout> | null = null

type SuggestSection = 'topics' | 'tags' | 'users' | 'sections' | 'saved_searches'

const flatSuggestions = computed(() => {
  const items: Array<{ url: string; label: string }> = []
  suggestTopics.value.forEach((item) => items.push({ url: item.url, label: item.title || '' }))
  suggestTags.value.forEach((item) => items.push({ url: item.url, label: `#${item.name}` }))
  suggestUsers.value.forEach((item) => items.push({ url: item.url, label: `@${item.username}` }))
  suggestSections.value.forEach((item) => items.push({
    url: item.url,
    label: item.category ? `${item.category} / ${item.name}` : (item.name || ''),
  }))
  suggestSavedSearches.value.forEach((item) => items.push({ url: item.url, label: t('forum.search.savedPrefix', { name: item.name || '' }) }))
  return items
})

watch(q, (value) => {
  if (!props.suggestUrl || value.trim().length < 2) {
    suggestOpen.value = false
    return
  }
  if (suggestTimer) clearTimeout(suggestTimer)
  suggestTimer = setTimeout(() => fetchSuggestions(value.trim()), 250)
})

onBeforeUnmount(() => {
  if (suggestTimer) clearTimeout(suggestTimer)
})

async function fetchSuggestions(query: string) {
  if (!props.suggestUrl) return
  suggestLoading.value = true
  try {
    const response = await fetch(`${props.suggestUrl}?q=${encodeURIComponent(query)}`, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (!response.ok) return
    const data = await response.json()
    suggestTopics.value = data.topics || []
    suggestTags.value = data.tags || []
    suggestUsers.value = data.users || []
    suggestSections.value = data.sections || []
    suggestSavedSearches.value = data.saved_searches || []
    suggestActiveIndex.value = -1
    suggestOpen.value = !!(
      suggestTopics.value.length
      || suggestTags.value.length
      || suggestUsers.value.length
      || suggestSections.value.length
      || suggestSavedSearches.value.length
    )
  } finally {
    suggestLoading.value = false
  }
}

function pickSuggestion(url: string) {
  suggestOpen.value = false
  suggestActiveIndex.value = -1
  router.visit(url)
}

function hideSuggestions() {
  setTimeout(() => {
    suggestOpen.value = false
    suggestActiveIndex.value = -1
  }, 150)
}

function suggestGlobalIndex(section: SuggestSection, localIndex: number) {
  let offset = 0
  if (section === 'topics') return offset + localIndex
  offset += suggestTopics.value.length
  if (section === 'tags') return offset + localIndex
  offset += suggestTags.value.length
  if (section === 'users') return offset + localIndex
  offset += suggestUsers.value.length
  if (section === 'sections') return offset + localIndex
  offset += suggestSections.value.length
  return offset + localIndex
}

function isSuggestActive(section: SuggestSection, localIndex: number) {
  return suggestActiveIndex.value === suggestGlobalIndex(section, localIndex)
}

function onSuggestKeydown(event: KeyboardEvent) {
  if (!suggestOpen.value || !flatSuggestions.value.length) return

  if (event.key === 'ArrowDown') {
    event.preventDefault()
    const next = suggestActiveIndex.value < 0 ? 0 : suggestActiveIndex.value + 1
    suggestActiveIndex.value = Math.min(next, flatSuggestions.value.length - 1)
  } else if (event.key === 'ArrowUp') {
    event.preventDefault()
    const next = suggestActiveIndex.value < 0 ? flatSuggestions.value.length - 1 : suggestActiveIndex.value - 1
    suggestActiveIndex.value = Math.max(next, 0)
  } else if (event.key === 'Enter' && suggestActiveIndex.value >= 0) {
    event.preventDefault()
    pickSuggestion(flatSuggestions.value[suggestActiveIndex.value].url)
  } else if (event.key === 'Escape') {
    event.preventDefault()
    suggestOpen.value = false
    suggestActiveIndex.value = -1
  }
}

watch(() => props.query, (value) => { q.value = value })
watch(() => props.author, (value) => { author.value = value })
watch(() => props.tag, (value) => { tagSlug.value = value })
watch(() => props.solved, (value) => { solved.value = value })

function searchParams() {
  return {
    q: q.value,
    section: sectionSlug.value || undefined,
    category: categorySlug.value || undefined,
    author: author.value || undefined,
    tag: tagSlug.value || undefined,
    solved: solved.value || undefined,
    locked: locked.value || undefined,
    pinned: pinned.value || undefined,
    wiki: wiki.value || undefined,
    featured: featured.value || undefined,
    poll: poll.value || undefined,
    noreplies: noreplies.value || undefined,
    title_only: titleOnly.value ? '1' : undefined,
    posts_only: postsOnly.value ? '1' : undefined,
    assigned: assigned.value || undefined,
    mine: mine.value || undefined,
    scope: scope.value || undefined,
    created_after: createdAfter.value || undefined,
    created_before: createdBefore.value || undefined,
    topic_sort: topicSort.value !== 'recent' ? topicSort.value : undefined,
    post_sort: postSort.value !== 'recent' ? postSort.value : undefined,
  }
}

function search() {
  router.get(routes.forumSearch, searchParams(), { preserveState: true })
}

function removeExcludeTerm(term: string) {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  q.value = q.value
    .replace(new RegExp(`(^|\\s)-${escaped}(?=\\s|$)`, 'g'), ' ')
    .replace(/\s+/g, ' ')
    .trim()
  router.get(routes.forumSearch, searchParams(), { preserveState: true })
}

function removeActiveFilter(filter: { param: string; value?: string | null }) {
  if (filter.param === 'exclude') {
    if (filter.value) removeExcludeTerm(filter.value)
    return
  }
  const clear: Record<string, () => void> = {
    q: () => { q.value = '' },
    section: () => { sectionSlug.value = '' },
    category: () => { categorySlug.value = '' },
    author: () => { author.value = '' },
    tag: () => { tagSlug.value = '' },
    solved: () => { solved.value = '' },
    locked: () => { locked.value = '' },
    pinned: () => { pinned.value = '' },
    wiki: () => { wiki.value = '' },
    featured: () => { featured.value = '' },
    poll: () => { poll.value = '' },
    noreplies: () => { noreplies.value = '' },
    assigned: () => { assigned.value = '' },
    mine: () => { mine.value = '' },
    scope: () => { scope.value = '' },
    created_after: () => { createdAfter.value = '' },
    created_before: () => { createdBefore.value = '' },
    title_only: () => { titleOnly.value = false },
    posts_only: () => { postsOnly.value = false },
    topic_sort: () => { topicSort.value = 'recent' },
    post_sort: () => { postSort.value = 'recent' },
  }
  clear[filter.param]?.()
  router.get(routes.forumSearch, searchParams(), { preserveState: true })
}

async function copySearchLink() {
  const params = new URLSearchParams()
  const data = searchParams()
  Object.entries(data).forEach(([key, value]) => {
    if (value !== undefined && value !== '') params.set(key, String(value))
  })
  const url = `${window.location.origin}${routes.forumSearch}?${params.toString()}`
  try {
    await navigator.clipboard.writeText(url)
    shareCopied.value = true
    setTimeout(() => { shareCopied.value = false }, 2000)
  } catch {
    await prompt({
      title: t('forum.search.copyLink'),
      defaultValue: url,
    })
  }
}

const liveSearch = ref(true)
let liveSearchTimer: ReturnType<typeof setTimeout> | null = null

watch(q, (value) => {
  if (!liveSearch.value) return
  const trimmed = value.trim()
  if (trimmed.length < 2) return
  if (liveSearchTimer) clearTimeout(liveSearchTimer)
  liveSearchTimer = setTimeout(() => {
    router.get(routes.forumSearch, searchParams(), {
      preserveState: true,
      preserveScroll: true,
      only: ['query', 'topics', 'posts', 'topicsPagination', 'postsPagination'],
    })
  }, 450)
})

onBeforeUnmount(() => {
  if (liveSearchTimer) clearTimeout(liveSearchTimer)
})

function saveFilters() {
  return {
    section: sectionSlug.value,
    category: categorySlug.value,
    author: author.value,
    tag: tagSlug.value,
    solved: solved.value,
    locked: locked.value,
    pinned: pinned.value,
    wiki: wiki.value,
    featured: featured.value,
    poll: poll.value,
    noreplies: noreplies.value,
    title_only: titleOnly.value ? '1' : '',
    posts_only: postsOnly.value ? '1' : '',
    assigned: assigned.value,
    mine: mine.value,
    scope: scope.value,
    created_after: createdAfter.value,
    created_before: createdBefore.value,
    topic_sort: topicSort.value,
    post_sort: postSort.value,
  }
}

async function saveSearch() {
  if (!props.saveSearchUrl || !saveName.value.trim()) return
  saving.value = true
  saveError.value = ''
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(props.saveSearchUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        saved_search: {
          name: saveName.value.trim(),
          query: q.value,
          notify_daily: saveNotifyDaily.value,
          webhook_url: saveWebhookUrl.value.trim() || null,
          filters: saveFilters(),
        },
      }),
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      saveError.value = data.error || t('forum.search.saveFailed')
      return
    }
    saveName.value = ''
    saveNotifyDaily.value = false
    saveWebhookUrl.value = ''
    router.reload({ only: ['savedSearches'] })
  } finally {
    saving.value = false
  }
}

async function deleteSearchHistory(deleteUrl: string) {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
  await fetch(deleteUrl, {
    method: 'DELETE',
    headers: { 'X-CSRF-Token': token, Accept: 'application/json' },
    credentials: 'same-origin',
  })
  router.reload({ only: ['searchHistories'] })
}

async function clearSearchHistory() {
  const ok = await confirm({
    title: t('forum.search.clearHistory'),
    message: t('forum.search.clearHistoryConfirm'),
    confirmLabel: t('forum.search.clear'),
    variant: 'destructive',
  })
  if (!props.clearSearchHistoryUrl || !ok) return
  router.delete(props.clearSearchHistoryUrl, { preserveScroll: true })
}

async function deleteSavedSearch(deleteUrl: string) {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
  await fetch(deleteUrl, {
    method: 'DELETE',
    headers: { 'X-CSRF-Token': token, Accept: 'application/json' },
    credentials: 'same-origin',
  })
  router.reload({ only: ['savedSearches'] })
}

const togglingNotifyId = ref<number | null>(null)
const editingSearchId = ref<number | null>(null)
const editingSearchName = ref('')
const renamingSearchId = ref<number | null>(null)

async function toggleSavedSearchNotify(search: { id: number; notify_daily?: boolean; update_url?: string }) {
  if (!search.update_url) return
  togglingNotifyId.value = search.id
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(search.update_url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        saved_search: { notify_daily: !search.notify_daily },
      }),
    })
    if (response.ok) {
      router.reload({ only: ['savedSearches'] })
    }
  } finally {
    togglingNotifyId.value = null
  }
}

async function toggleSavedSearchNotifyInApp(search: { id: number; notify_in_app?: boolean; update_url?: string }) {
  if (!search.update_url) return
  togglingNotifyId.value = search.id
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(search.update_url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        saved_search: { notify_in_app: !search.notify_in_app },
      }),
    })
    if (response.ok) {
      router.reload({ only: ['savedSearches'] })
    }
  } finally {
    togglingNotifyId.value = null
  }
}

function startRenameSearch(search: { id: number; name: string }) {
  editingSearchId.value = search.id
  editingSearchName.value = search.name
}

function cancelRenameSearch() {
  editingSearchId.value = null
  editingSearchName.value = ''
}

async function saveRenameSearch(search: { id: number; update_url?: string }) {
  if (!search.update_url || !editingSearchName.value.trim()) return
  renamingSearchId.value = search.id
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(search.update_url, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        saved_search: { name: editingSearchName.value.trim() },
      }),
    })
    if (response.ok) {
      editingSearchId.value = null
      editingSearchName.value = ''
      router.reload({ only: ['savedSearches'] })
    }
  } finally {
    renamingSearchId.value = null
  }
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('nav.search'), current: true },
  ]" />

  <PageHeader :title="t('forum.search.title')" :subtitle="t('forum.search.subtitle')" />

  <form class="mb-4 flex max-w-2xl flex-wrap gap-2" @submit.prevent="search">
    <div class="relative min-w-[200px] flex-1">
      <Input
        v-model="q"
        :placeholder="t('forum.search.keywordPlaceholder')"
        class="w-full"
        autocomplete="off"
        @focus="q.trim().length >= 2 && suggestUrl && fetchSuggestions(q.trim())"
        @blur="hideSuggestions"
        @keydown="onSuggestKeydown"
      />
      <div
        v-if="suggestOpen && suggestUrl"
        class="absolute z-20 mt-1 max-h-64 w-full overflow-y-auto rounded-md border bg-background shadow-md"
      >
        <p v-if="suggestLoading" class="px-3 py-2 text-xs text-muted-foreground">{{ t('forum.search.suggestLoading') }}</p>
        <template v-else>
          <div v-if="suggestTopics.length" class="border-b px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">{{ t('forum.search.suggestTopics') }}</p>
            <button
              v-for="(item, index) in suggestTopics"
              :key="item.url"
              type="button"
              class="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
              :class="{ 'bg-muted': isSuggestActive('topics', index) }"
              @mousedown.prevent="pickSuggestion(item.url)"
            >
              {{ item.title }}
            </button>
          </div>
          <div v-if="suggestTags.length" class="border-b px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">{{ t('forum.search.suggestTags') }}</p>
            <button
              v-for="(item, index) in suggestTags"
              :key="item.url"
              type="button"
              class="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
              :class="{ 'bg-muted': isSuggestActive('tags', index) }"
              @mousedown.prevent="pickSuggestion(item.url)"
            >
              #{{ item.name }}
            </button>
          </div>
          <div v-if="suggestUsers.length" class="border-b px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">{{ t('forum.search.suggestUsers') }}</p>
            <button
              v-for="(item, index) in suggestUsers"
              :key="item.url"
              type="button"
              class="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
              :class="{ 'bg-muted': isSuggestActive('users', index) }"
              @mousedown.prevent="pickSuggestion(item.url)"
            >
              @{{ item.username }}
            </button>
          </div>
          <div v-if="suggestSections.length" class="border-b px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">{{ t('forum.search.suggestSections') }}</p>
            <button
              v-for="(item, index) in suggestSections"
              :key="item.url"
              type="button"
              class="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
              :class="{ 'bg-muted': isSuggestActive('sections', index) }"
              @mousedown.prevent="pickSuggestion(item.url)"
            >
              {{ item.category ? `${item.category} / ${item.name}` : item.name }}
            </button>
          </div>
          <div v-if="suggestSavedSearches.length" class="px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">{{ t('forum.search.suggestSaved') }}</p>
            <button
              v-for="(item, index) in suggestSavedSearches"
              :key="item.url"
              type="button"
              class="block w-full rounded px-2 py-1.5 text-left text-sm hover:bg-muted"
              :class="{ 'bg-muted': isSuggestActive('saved_searches', index) }"
              @mousedown.prevent="pickSuggestion(item.url)"
            >
              {{ item.name }}
            </button>
          </div>
        </template>
      </div>
    </div>
    <Select v-model="sectionSlug" :options="sectionSelectOptions" size="sm" />
    <Input v-model="author" :placeholder="t('forum.search.authorPlaceholder')" class="w-36" />
    <Input v-model="createdAfter" type="date" class="w-36" :title="t('forum.search.dateFrom')" />
    <Input v-model="createdBefore" type="date" class="w-36" :title="t('forum.search.dateTo')" />
    <Select v-model="tagSlug" :options="tagSelectOptions" size="sm" />
    <Select v-model="solved" :options="solvedOptions" size="sm" />
    <Select v-model="topicSort" :options="topicSortOptions" size="sm" :disabled="postsOnly" />
    <Select v-model="postSort" :options="postSortOptions" size="sm" :disabled="titleOnly" />
    <label class="flex h-9 items-center gap-2 rounded-md border px-3 text-sm">
      <Checkbox v-model="titleOnly" />
      {{ t('forum.search.titleOnly') }}
    </label>
    <label class="flex h-9 items-center gap-2 rounded-md border px-3 text-sm">
      <Checkbox v-model="postsOnly" />
      {{ t('forum.search.postsOnly') }}
    </label>
    <button type="button" class="rounded-md border px-3 py-2 text-sm" @click="showAdvanced = !showAdvanced">
      {{ showAdvanced ? t('forum.search.hideAdvanced') : t('forum.search.showAdvanced') }}
    </button>
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">{{ t('forum.search.submit') }}</button>
    <button type="button" class="rounded-md border px-3 py-2 text-sm" @click="copySearchLink">
      {{ shareCopied ? t('forum.search.linkCopied') : t('forum.search.copyLinkBtn') }}
    </button>
  </form>

  <div v-if="activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('forum.search.activeFilters') }}</span>
    <span
      v-for="filter in activeFilters"
      :key="`${filter.param}-${filter.value || filter.label}`"
      class="inline-flex items-center gap-1 rounded-full border border-primary/30 bg-primary/5 px-2.5 py-0.5 text-xs text-primary"
      :class="filter.param === 'exclude' ? 'border-destructive/30 bg-destructive/5 text-destructive' : ''"
    >
      {{ filter.label }}
      <button
        type="button"
        class="hover:opacity-70"
        :title="t('forum.search.removeFilter')"
        @click="removeActiveFilter(filter)"
      >×</button>
    </span>
  </div>

  <p class="mb-4 max-w-2xl text-xs text-muted-foreground">
    {{ t('forum.search.excludeSyntax') }} <code class="rounded bg-muted px-1">-</code> {{ t('forum.search.excludeSyntaxExample') }}
    <code class="rounded bg-muted px-1">ruby tutorial -spam -offtopic</code>
  </p>

  <div v-if="excludeTerms?.length && !activeFilters?.length" class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-xs text-muted-foreground">{{ t('forum.search.excludeTerms') }}</span>
    <span
      v-for="term in excludeTerms"
      :key="term"
      class="inline-flex items-center gap-1 rounded-full border border-destructive/30 bg-destructive/5 px-2.5 py-0.5 text-xs text-destructive"
    >
      −{{ term }}
      <button
        type="button"
        class="hover:text-destructive/80"
        :title="t('forum.search.removeExclude')"
        @click="removeExcludeTerm(term)"
      >×</button>
    </span>
  </div>

  <div v-if="showAdvanced" class="mb-6 flex max-w-2xl flex-wrap gap-2 rounded-lg border p-4">
    <Select v-if="categories?.length" v-model="categorySlug" :options="categorySelectOptions" size="sm" />
    <Select v-model="locked" :options="lockedOptions" size="sm" />
    <Select v-model="pinned" :options="pinnedOptions" size="sm" />
    <Select v-model="wiki" :options="wikiOptions" size="sm" />
    <Select v-model="featured" :options="featuredOptions" size="sm" />
    <Select v-model="poll" :options="pollOptions" size="sm" />
    <Select v-model="noreplies" :options="norepliesOptions" size="sm" />
    <Select v-if="loggedIn" v-model="assigned" :options="assignedOptions" size="sm" />
    <Select v-if="loggedIn" v-model="mine" :options="mineOptions" size="sm" />
    <Select v-if="loggedIn" v-model="scope" :options="scopeOptions" size="sm" />
  </div>

  <div v-if="loggedIn && saveSearchUrl" class="mb-6 flex flex-wrap items-end gap-2 rounded-lg border p-4">
    <div class="space-y-1">
      <label class="text-sm font-medium">{{ t('forum.search.saveCurrentSearch') }}</label>
      <Input v-model="saveName" :placeholder="t('forum.search.searchNamePlaceholder')" class="w-48" :disabled="atSavedSearchLimit" />
      <label class="flex items-center gap-2 text-sm text-muted-foreground">
        <Checkbox v-model="saveNotifyDaily" :disabled="atSavedSearchLimit" />
        {{ t('forum.search.notifyDaily') }}
      </label>
      <Input v-model="saveWebhookUrl" :placeholder="t('forum.search.webhookPlaceholder')" class="w-64" :disabled="atSavedSearchLimit" />
      <p v-if="savedSearchLimit" class="text-xs text-muted-foreground">
        {{ t('forum.search.savedCount', { count: savedSearchCount ?? 0, limit: savedSearchLimit }) }}
      </p>
      <p v-if="atSavedSearchLimit" class="text-xs text-destructive">{{ t('forum.search.savedLimitReached') }}</p>
    </div>
    <Button type="button" variant="outline" :disabled="saving || !saveName.trim() || atSavedSearchLimit" @click="saveSearch">
      {{ saving ? t('forum.search.saving') : t('forum.search.saveSearch') }}
    </Button>
    <p v-if="saveError" class="text-sm text-destructive">{{ saveError }}</p>
  </div>

  <div v-if="searchHistories?.length" class="mb-6">
    <div class="mb-2 flex flex-wrap items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ t('forum.search.recentSearches') }}</h2>
      <div class="flex gap-3">
        <a
          v-if="searchFeedsOpmlUrl"
          :href="searchFeedsOpmlUrl"
          class="text-xs text-primary hover:underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          {{ t('forum.search.exportMergedOpml') }}
        </a>
        <a
          v-if="searchHistoriesOpmlUrl"
          :href="searchHistoriesOpmlUrl"
          class="text-xs text-primary hover:underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          {{ t('forum.search.exportOpml') }}
        </a>
        <button
          v-if="clearSearchHistoryUrl"
          type="button"
          class="text-xs text-muted-foreground hover:text-destructive"
          @click="clearSearchHistory"
        >
          {{ t('forum.search.clearHistoryBtn') }}
        </button>
      </div>
    </div>
    <div class="flex flex-wrap gap-2">
      <span
        v-for="history in searchHistories"
        :key="history.id"
        class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm"
      >
        <Link :href="history.url" class="hover:underline">{{ history.query || t('forum.search.filterSearch') }}</Link>
        <span v-for="label in history.filter_labels || []" :key="label" class="text-[10px] text-muted-foreground">{{ label }}</span>
        <span class="text-[10px] text-muted-foreground">{{ history.searched_at }}</span>
        <button type="button" class="text-muted-foreground hover:text-destructive" :title="t('forum.search.delete')" @click="deleteSearchHistory(history.delete_url)">×</button>
      </span>
    </div>
  </div>

  <div v-if="savedSearches?.length" class="mb-6 flex flex-wrap gap-2">
    <span class="text-sm text-muted-foreground">{{ t('forum.search.savedLabel') }}</span>
    <a
      v-if="savedSearchesOpmlUrl"
      :href="savedSearchesOpmlUrl"
      class="text-xs text-primary hover:underline"
      target="_blank"
      rel="noopener noreferrer"
    >
      {{ t('forum.search.exportOpml') }}
    </a>
    <span v-for="search in savedSearches" :key="search.id" class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm">
      <template v-if="editingSearchId === search.id">
        <Input
          v-model="editingSearchName"
          class="h-7 w-32 text-sm"
          @keydown.enter="saveRenameSearch(search)"
          @keydown.escape="cancelRenameSearch"
        />
        <button
          type="button"
          class="text-primary hover:underline"
          :disabled="renamingSearchId === search.id || !editingSearchName.trim()"
          @click="saveRenameSearch(search)"
        >
          {{ t('forum.search.save') }}
        </button>
        <button type="button" class="text-muted-foreground" @click="cancelRenameSearch">{{ t('forum.search.cancel') }}</button>
      </template>
      <template v-else>
        <Link :href="search.url" class="hover:underline">{{ search.name }}</Link>
        <button
          v-if="search.update_url"
          type="button"
          class="text-muted-foreground hover:text-foreground"
          :title="t('forum.search.rename')"
          @click="startRenameSearch(search)"
        >
          ✎
        </button>
        <button
          v-if="search.update_url"
          type="button"
          class="text-[10px] transition-opacity"
          :class="search.notify_daily ? 'text-primary' : 'text-muted-foreground opacity-50 hover:opacity-100'"
          :disabled="togglingNotifyId === search.id"
          :title="search.notify_daily ? t('forum.search.disableDailyEmail') : t('forum.search.enableDailyEmail')"
          @click="toggleSavedSearchNotify(search)"
        >
          📧
        </button>
        <button
          v-if="search.update_url"
          type="button"
          class="text-[10px] transition-opacity"
          :class="search.notify_in_app !== false ? 'text-primary' : 'text-muted-foreground opacity-50 hover:opacity-100'"
          :disabled="togglingNotifyId === search.id"
          :title="search.notify_in_app !== false ? t('forum.search.disableInApp') : t('forum.search.enableInApp')"
          @click="toggleSavedSearchNotifyInApp(search)"
        >
          🔔
        </button>
        <a
          v-if="search.rss_url"
          :href="search.rss_url"
          class="text-[10px] text-muted-foreground hover:text-foreground"
          :title="t('forum.search.rssFeed')"
          target="_blank"
          rel="noopener noreferrer"
        >
          RSS
        </a>
        <span
          v-if="search.webhook_url"
          class="text-[10px] text-muted-foreground"
          :title="t('forum.search.webhookConfigured')"
        >
          Hook
        </span>
        <button type="button" class="text-muted-foreground hover:text-destructive" :title="t('forum.search.delete')" @click="deleteSavedSearch(search.delete_url)">×</button>
      </template>
    </span>
  </div>

  <template v-if="query">
    <div class="mb-3 flex items-center justify-between gap-2">
      <h2 class="text-sm font-semibold">{{ t('forum.search.topics') }}</h2>
      <div class="flex gap-3">
        <a
          v-if="searchRssUrl"
          :href="searchRssUrl"
          class="text-xs text-primary hover:underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          {{ t('forum.search.rssSubscribe') }}
        </a>
        <a
          v-if="searchOpmlUrl"
          :href="searchOpmlUrl"
          class="text-xs text-primary hover:underline"
          target="_blank"
          rel="noopener noreferrer"
        >
          {{ t('forum.search.exportOpml') }}
        </a>
      </div>
    </div>
    <div v-if="canBulkModerate && bulkModerateUrl && topics.length" class="mb-3 flex flex-wrap gap-2">
      <BulkModerateToolbar :count="selectedTopicIds.length" @moderate="bulkModerate" />
    </div>
    <TopicListTable
      v-if="topics.length"
      :topics="topics"
      show-views
      show-participants
      class="mb-4"
      :selectable="!!(canBulkModerate && bulkModerateUrl)"
      :selected-ids="selectedTopicIds"
      @update:selected-ids="selectedTopicIds = $event"
    />
    <Pagination v-if="topics.length" :pagination="topicsPagination" :base-path="routes.forumSearch" page-param="topic_page" class="mb-8" />
    <p v-else class="mb-8 text-sm text-muted-foreground">{{ t('forum.search.noTopics') }}</p>

    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.search.postsHeading') }}</h2>
    <div v-if="posts.length" class="rounded-lg border">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b text-left">
            <th class="p-3">{{ t('forum.search.content') }}</th>
            <th class="p-3">{{ t('forum.search.topic') }}</th>
            <th class="p-3">{{ t('forum.search.author') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="post in posts" :key="post.id" class="border-b">
            <td class="p-3">
              <span v-if="post.body_html" v-html="post.body_html" />
              <span v-else>{{ post.body }}</span>
            </td>
            <td class="p-3"><Link :href="post.topic_url" class="hover:underline">{{ post.topic_title }}</Link></td>
            <td class="p-3">{{ post.author }}</td>
          </tr>
        </tbody>
      </table>
      <Pagination :pagination="postsPagination" :base-path="routes.forumSearch" page-param="post_page" />
    </div>
    <p v-else class="text-sm text-muted-foreground">{{ t('forum.search.noPosts') }}</p>
  </template>
</template>
