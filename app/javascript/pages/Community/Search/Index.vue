<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref, watch, computed, onBeforeUnmount } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export type SearchTopic = TopicListItem

export interface SearchPost {
  id: number
  body: string
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
  savedSearches?: Array<{ id: number; name: string; query: string; url: string; delete_url: string; notify_daily?: boolean }>
  loggedIn?: boolean
  forumStaff?: boolean
  saveSearchUrl?: string | null
  suggestUrl?: string | null
}>()

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
const saving = ref(false)
const saveError = ref('')

type SuggestItem = { title?: string; name?: string; username?: string; url: string }
const suggestOpen = ref(false)
const suggestLoading = ref(false)
const suggestTopics = ref<SuggestItem[]>([])
const suggestTags = ref<SuggestItem[]>([])
const suggestUsers = ref<SuggestItem[]>([])
const suggestActiveIndex = ref(-1)
let suggestTimer: ReturnType<typeof setTimeout> | null = null

const flatSuggestions = computed(() => {
  const items: Array<{ url: string; label: string }> = []
  suggestTopics.value.forEach((item) => items.push({ url: item.url, label: item.title || '' }))
  suggestTags.value.forEach((item) => items.push({ url: item.url, label: `#${item.name}` }))
  suggestUsers.value.forEach((item) => items.push({ url: item.url, label: `@${item.username}` }))
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
    suggestActiveIndex.value = -1
    suggestOpen.value = !!(suggestTopics.value.length || suggestTags.value.length || suggestUsers.value.length)
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

function suggestGlobalIndex(section: 'topics' | 'tags' | 'users', localIndex: number) {
  if (section === 'topics') return localIndex
  if (section === 'tags') return suggestTopics.value.length + localIndex
  return suggestTopics.value.length + suggestTags.value.length + localIndex
}

function isSuggestActive(section: 'topics' | 'tags' | 'users', localIndex: number) {
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
          filters: saveFilters(),
        },
      }),
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      saveError.value = data.error || '保存失败'
      return
    }
    saveName.value = ''
    saveNotifyDaily.value = false
    router.reload({ only: ['savedSearches'] })
  } finally {
    saving.value = false
  }
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
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '搜索', current: true },
  ]" />

  <PageHeader title="搜索论坛" subtitle="支持 in:分区、tag:标签、is:solved/is:locked/is:featured/is:unlisted、has:poll/has:noreplies 等语法" />

  <form class="mb-4 flex max-w-2xl flex-wrap gap-2" @submit.prevent="search">
    <div class="relative min-w-[200px] flex-1">
      <Input
        v-model="q"
        placeholder="输入关键词..."
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
        <p v-if="suggestLoading" class="px-3 py-2 text-xs text-muted-foreground">搜索建议…</p>
        <template v-else>
          <div v-if="suggestTopics.length" class="border-b px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">主题</p>
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
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">标签</p>
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
          <div v-if="suggestUsers.length" class="px-2 py-1">
            <p class="px-1 py-1 text-[10px] font-semibold uppercase text-muted-foreground">用户</p>
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
        </template>
      </div>
    </div>
    <select v-model="sectionSlug" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部分区</option>
      <option v-for="sec in sections" :key="sec.slug" :value="sec.slug">
        {{ sec.category ? `${sec.category} / ` : '' }}{{ sec.name }}
      </option>
    </select>
    <Input v-model="author" placeholder="作者用户名" class="w-36" />
    <Input v-model="createdAfter" type="date" class="w-36" title="起始日期" />
    <Input v-model="createdBefore" type="date" class="w-36" title="截止日期" />
    <select v-model="tagSlug" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部标签</option>
      <option v-for="t in tags" :key="t.slug" :value="t.slug">#{{ t.name }}</option>
    </select>
    <select v-model="solved" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部状态</option>
      <option value="unsolved">未解决</option>
      <option value="solved">已解决</option>
    </select>
    <select v-model="topicSort" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="recent">主题：最新</option>
      <option value="oldest">主题：最早</option>
    </select>
    <select v-model="postSort" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="recent">帖子：最新</option>
      <option value="oldest">帖子：最早</option>
    </select>
    <button type="button" class="rounded-md border px-3 py-2 text-sm" @click="showAdvanced = !showAdvanced">
      {{ showAdvanced ? '收起高级' : '高级筛选' }}
    </button>
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">搜索</button>
  </form>

  <div v-if="showAdvanced" class="mb-6 flex max-w-2xl flex-wrap gap-2 rounded-lg border p-4">
    <select v-if="categories?.length" v-model="categorySlug" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部分类</option>
      <option v-for="cat in categories" :key="cat.slug" :value="cat.slug">{{ cat.name }}</option>
    </select>
    <select v-model="locked" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">锁定状态</option>
      <option value="locked">已锁定</option>
      <option value="unlocked">未锁定</option>
    </select>
    <select v-model="pinned" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">置顶状态</option>
      <option value="pinned">已置顶</option>
      <option value="unpinned">未置顶</option>
    </select>
    <select v-model="wiki" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">Wiki</option>
      <option value="wiki">Wiki 主题</option>
      <option value="nonwiki">非 Wiki</option>
    </select>
    <select v-model="featured" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">精选</option>
      <option value="featured">精选主题</option>
    </select>
    <select v-model="poll" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">投票</option>
      <option value="poll">含投票</option>
    </select>
    <select v-model="noreplies" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">回复</option>
      <option value="noreplies">无回复</option>
    </select>
    <select v-if="loggedIn" v-model="assigned" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">分配</option>
      <option value="assigned">已分配</option>
      <option value="unassigned">未分配</option>
    </select>
    <select v-if="loggedIn" v-model="mine" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">范围</option>
      <option value="mine">我的主题</option>
    </select>
    <select v-if="loggedIn" v-model="scope" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">订阅</option>
      <option value="bookmarks">我的收藏</option>
      <option value="watching">正在关注</option>
      <option value="unread">未读</option>
    </select>
  </div>

  <div v-if="loggedIn && saveSearchUrl" class="mb-6 flex flex-wrap items-end gap-2 rounded-lg border p-4">
    <div class="space-y-1">
      <label class="text-sm font-medium">保存当前搜索</label>
      <Input v-model="saveName" placeholder="搜索名称" class="w-48" />
      <label class="flex items-center gap-2 text-sm text-muted-foreground">
        <input v-model="saveNotifyDaily" type="checkbox" class="rounded border-input" />
        每日邮件提醒新结果
      </label>
    </div>
    <Button type="button" variant="outline" :disabled="saving || !saveName.trim()" @click="saveSearch">
      {{ saving ? '保存中…' : '保存搜索' }}
    </Button>
    <p v-if="saveError" class="text-sm text-destructive">{{ saveError }}</p>
  </div>

  <div v-if="savedSearches?.length" class="mb-6 flex flex-wrap gap-2">
    <span class="text-sm text-muted-foreground">已保存：</span>
    <span v-for="search in savedSearches" :key="search.id" class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm">
      <Link :href="search.url" class="hover:underline">{{ search.name }}</Link>
      <span v-if="search.notify_daily" class="text-[10px] text-primary" title="已开启每日邮件提醒">📧</span>
      <button type="button" class="text-muted-foreground hover:text-destructive" @click="deleteSavedSearch(search.delete_url)">×</button>
    </span>
  </div>

  <template v-if="query">
    <h2 class="mb-3 text-sm font-semibold">主题</h2>
    <TopicListTable v-if="topics.length" :topics="topics" show-views show-participants class="mb-4" />
    <Pagination v-if="topics.length" :pagination="topicsPagination" :base-path="routes.forumSearch" page-param="topic_page" class="mb-8" />
    <p v-else class="mb-8 text-sm text-muted-foreground">未找到相关主题。</p>

    <h2 class="mb-3 text-sm font-semibold">帖子</h2>
    <div v-if="posts.length" class="rounded-lg border">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b text-left">
            <th class="p-3">内容</th>
            <th class="p-3">主题</th>
            <th class="p-3">作者</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="post in posts" :key="post.id" class="border-b">
            <td class="p-3">{{ post.body }}</td>
            <td class="p-3"><Link :href="post.topic_url" class="hover:underline">{{ post.topic_title }}</Link></td>
            <td class="p-3">{{ post.author }}</td>
          </tr>
        </tbody>
      </table>
      <Pagination :pagination="postsPagination" :base-path="routes.forumSearch" page-param="post_page" />
    </div>
    <p v-else class="text-sm text-muted-foreground">未找到相关帖子。</p>
  </template>
</template>
