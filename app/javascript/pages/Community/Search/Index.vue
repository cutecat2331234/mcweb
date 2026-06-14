<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref, watch } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Input from '@/components/ui/Input.vue'
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
  author: string
  tag: string
  solved: string
  createdAfter?: string
  createdBefore?: string
  topicSort?: string
  postSort?: string
  sections: SectionOption[]
  tags: Array<{ slug: string; name: string }>
  topics: SearchTopic[]
  posts: SearchPost[]
  topicsPagination: PaginationMeta
  postsPagination: PaginationMeta
}>()

const q = ref(props.query)
const sectionSlug = ref(props.section || '')
const author = ref(props.author)
const tagSlug = ref(props.tag)
const solved = ref(props.solved)
const createdAfter = ref(props.createdAfter || '')
const createdBefore = ref(props.createdBefore || '')
const topicSort = ref(props.topicSort || 'recent')
const postSort = ref(props.postSort || 'recent')

watch(() => props.query, (value) => { q.value = value })
watch(() => props.author, (value) => { author.value = value })
watch(() => props.tag, (value) => { tagSlug.value = value })
watch(() => props.solved, (value) => { solved.value = value })

function search() {
  router.get(routes.forumSearch, {
    q: q.value,
    section: sectionSlug.value || undefined,
    author: author.value || undefined,
    tag: tagSlug.value || undefined,
    solved: solved.value || undefined,
    created_after: createdAfter.value || undefined,
    created_before: createdBefore.value || undefined,
    topic_sort: topicSort.value !== 'recent' ? topicSort.value : undefined,
    post_sort: postSort.value !== 'recent' ? postSort.value : undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '搜索', current: true },
  ]" />

  <PageHeader title="搜索论坛" subtitle="支持 in:分区、tag:标签、is:solved/is:locked/is:pinned/is:wiki/is:featured/is:announcement 等语法" />

  <form class="mb-8 flex max-w-2xl flex-wrap gap-2" @submit.prevent="search">
    <Input v-model="q" placeholder="输入关键词..." class="min-w-[200px] flex-1" />
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
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">搜索</button>
  </form>

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
      <Pagination :pagination="postsPagination" :base-path="routes.forumSearch" query-param="post_page" />
    </div>
    <p v-else class="text-sm text-muted-foreground">未找到相关帖子。</p>
  </template>
</template>
