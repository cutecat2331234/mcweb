<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref, watch } from 'vue'
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
  assigned?: string
  assignee?: string
  locked?: string
  pinned?: string
  wiki?: string
  mine?: string
  scope?: string
  poll?: string
  noreplies?: string
  featured?: string
  announcement?: string
  unlisted?: string
  archived?: string
  images?: string
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
  savedSearches?: Array<{ id: number; name: string; query: string; url: string; delete_url: string }>
  loggedIn?: boolean
  forumStaff?: boolean
  saveSearchUrl?: string | null
  suggestUrl?: string
}>()

const q = ref(props.query)
const sectionSlug = ref(props.section || '')
const categorySlug = ref(props.category || '')
const author = ref(props.author)
const tagSlug = ref(props.tag)
const solved = ref(props.solved)
const assignedFilter = ref(props.assigned || '')
const assignee = ref(props.assignee || '')
const lockedFilter = ref(props.locked || '')
const pinnedFilter = ref(props.pinned || '')
const wikiFilter = ref(props.wiki || '')
const mineFilter = ref(props.mine || '')
const scopeFilter = ref(props.scope || '')
const pollFilter = ref(props.poll || '')
const norepliesFilter = ref(props.noreplies || '')
const featuredFilter = ref(props.featured || '')
const announcementFilter = ref(props.announcement || '')
const unlistedFilter = ref(props.unlisted || '')
const archivedFilter = ref(props.archived || '')
const imagesOnly = ref(props.images === 'images')
const createdAfter = ref(props.createdAfter || '')
const createdBefore = ref(props.createdBefore || '')
const topicSort = ref(props.topicSort || 'recent')
const postSort = ref(props.postSort || 'recent')
const saveName = ref('')
const saving = ref(false)
const saveError = ref('')
const suggestions = ref<{ topics: Array<{ title: string; url: string }>; tags: Array<{ name: string; url: string }>; users: Array<{ username: string; url: string }> } | null>(null)
let suggestTimer: ReturnType<typeof setTimeout> | null = null

watch(q, (value) => {
  if (!props.suggestUrl || value.length < 2) {
    suggestions.value = null
    return
  }
  if (suggestTimer) clearTimeout(suggestTimer)
  suggestTimer = setTimeout(async () => {
    try {
      const response = await fetch(`${props.suggestUrl}?q=${encodeURIComponent(value)}`, {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      })
      if (response.ok) suggestions.value = await response.json()
    } catch {
      suggestions.value = null
    }
  }, 300)
})

watch(() => props.query, (value) => { q.value = value })
watch(() => props.author, (value) => { author.value = value })
watch(() => props.tag, (value) => { tagSlug.value = value })
watch(() => props.solved, (value) => { solved.value = value })

function search() {
  router.get(routes.forumSearch, {
    q: q.value,
    section: sectionSlug.value || undefined,
    category: categorySlug.value || undefined,
    author: author.value || undefined,
    tag: tagSlug.value || undefined,
    solved: solved.value || undefined,
    assigned: assignedFilter.value || undefined,
    assignee: assignee.value || undefined,
    locked: lockedFilter.value || undefined,
    pinned: pinnedFilter.value || undefined,
    wiki: wikiFilter.value || undefined,
    mine: mineFilter.value || undefined,
    scope: scopeFilter.value || undefined,
    poll: pollFilter.value || undefined,
    noreplies: norepliesFilter.value || undefined,
    featured: featuredFilter.value || undefined,
    announcement: announcementFilter.value || undefined,
    unlisted: unlistedFilter.value || undefined,
    archived: archivedFilter.value || undefined,
    images: imagesOnly.value ? 'images' : undefined,
    created_after: createdAfter.value || undefined,
    created_before: createdBefore.value || undefined,
    topic_sort: topicSort.value !== 'recent' ? topicSort.value : undefined,
    post_sort: postSort.value !== 'recent' ? postSort.value : undefined,
  }, { preserveState: true })
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
          filters: {
            section: sectionSlug.value,
            category: categorySlug.value,
            author: author.value,
            tag: tagSlug.value,
            solved: solved.value,
            assigned: assignedFilter.value,
            assignee: assignee.value,
            locked: lockedFilter.value,
            pinned: pinnedFilter.value,
            wiki: wikiFilter.value,
            mine: mineFilter.value,
            scope: scopeFilter.value,
            poll: pollFilter.value,
            noreplies: norepliesFilter.value,
            featured: featuredFilter.value,
            announcement: announcementFilter.value,
            unlisted: unlistedFilter.value,
            archived: archivedFilter.value,
            images: imagesOnly.value ? 'images' : '',
            created_after: createdAfter.value,
            created_before: createdBefore.value,
            topic_sort: topicSort.value,
            post_sort: postSort.value,
          },
        },
      }),
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      saveError.value = data.error || '保存失败'
      return
    }
    saveName.value = ''
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

  <PageHeader title="搜索论坛" subtitle="支持 in:分区、category:分类、in:bookmarks、in:watching、in:unread、is:mine、is:assigned、assigned:me、has:images、tag:标签 等语法" />

  <form class="mb-8 flex max-w-2xl flex-wrap gap-2" @submit.prevent="search">
    <div class="relative min-w-[200px] flex-1">
      <Input v-model="q" placeholder="输入关键词..." class="w-full" />
      <div v-if="suggestions && (suggestions.topics.length || suggestions.tags.length || suggestions.users.length)" class="absolute z-10 mt-1 w-full rounded-md border bg-background p-2 shadow-md">
        <p v-for="topic in suggestions.topics" :key="topic.url" class="text-sm">
          <Link :href="topic.url" class="hover:underline">{{ topic.title }}</Link>
        </p>
        <p v-for="tag in suggestions.tags" :key="tag.url" class="text-sm text-muted-foreground">
          <Link :href="tag.url" class="hover:underline">#{{ tag.name }}</Link>
        </p>
        <p v-for="user in suggestions.users" :key="user.url" class="text-sm text-muted-foreground">
          <Link :href="user.url" class="hover:underline">@{{ user.username }}</Link>
        </p>
      </div>
    </div>
    <select v-model="sectionSlug" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部分区</option>
      <option v-for="sec in sections" :key="sec.slug" :value="sec.slug">
        {{ sec.category ? `${sec.category} / ` : '' }}{{ sec.name }}
      </option>
    </select>
    <select v-if="categories?.length" v-model="categorySlug" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部分类</option>
      <option v-for="cat in categories" :key="cat.slug" :value="cat.slug">{{ cat.name }}</option>
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
    <select v-model="assignedFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">指派状态</option>
      <option value="assigned">已指派</option>
      <option value="unassigned">未指派</option>
    </select>
    <Input v-model="assignee" placeholder="指派人（me 或用户名）" class="w-40" />
    <select v-if="loggedIn" v-model="scopeFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部主题</option>
      <option value="bookmarks">我的书签</option>
      <option value="watching">我的关注</option>
      <option value="unread">未读</option>
    </select>
    <select v-if="loggedIn" v-model="mineFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">不限作者</option>
      <option value="mine">我的主题</option>
    </select>
    <select v-model="lockedFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">锁定状态</option>
      <option value="locked">已锁定</option>
      <option value="unlocked">未锁定</option>
    </select>
    <select v-model="pinnedFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">置顶状态</option>
      <option value="pinned">已置顶</option>
    </select>
    <select v-model="wikiFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部类型</option>
      <option value="wiki">Wiki</option>
    </select>
    <select v-model="pollFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">投票</option>
      <option value="poll">含投票</option>
    </select>
    <select v-model="norepliesFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">回复数</option>
      <option value="noreplies">零回复</option>
    </select>
    <select v-model="featuredFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">精选</option>
      <option value="featured">仅精选</option>
    </select>
    <select v-model="announcementFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">公告</option>
      <option value="announcement">仅全站公告</option>
    </select>
    <template v-if="forumStaff">
      <select v-model="unlistedFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
        <option value="">列出状态</option>
        <option value="unlisted">未列出</option>
      </select>
      <select v-model="archivedFilter" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
        <option value="">归档</option>
        <option value="archived">已归档</option>
      </select>
    </template>
    <label class="flex h-9 items-center gap-2 text-sm">
      <input v-model="imagesOnly" type="checkbox" class="rounded border" />
      含图片
    </label>
    <select v-model="topicSort" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="recent">主题：最新</option>
      <option value="oldest">主题：最早</option>
      <option value="relevance">主题：相关度</option>
    </select>
    <select v-model="postSort" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="recent">帖子：最新</option>
      <option value="oldest">帖子：最早</option>
      <option value="relevance">帖子：相关度</option>
    </select>
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">搜索</button>
  </form>

  <div v-if="loggedIn && saveSearchUrl" class="mb-6 flex flex-wrap items-end gap-2 rounded-lg border p-4">
    <div class="space-y-1">
      <label class="text-sm font-medium">保存当前搜索</label>
      <Input v-model="saveName" placeholder="搜索名称" class="w-48" />
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
            <td class="p-3">
              <span v-if="post.body_html" v-html="post.body_html" />
              <span v-else>{{ post.body }}</span>
            </td>
            <td class="p-3"><Link :href="post.topic_url" class="hover:underline">{{ post.topic_title }}</Link></td>
            <td class="p-3">{{ post.author }}</td>
          </tr>
        </tbody>
      </table>
      <Pagination :pagination="postsPagination" :base-path="routes.forumSearch" query-param="post_page" />
    </div>
    <p v-else class="text-sm text-muted-foreground">未找到相关帖子。</p>
  </template>
</template>
