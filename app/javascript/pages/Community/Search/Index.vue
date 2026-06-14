<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { ref, watch } from 'vue'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Input from '@/components/ui/Input.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface SearchTopic {
  id: string
  title: string
  url: string
  last_posted_at: string | null
}

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
  sections: SectionOption[]
  topics: SearchTopic[]
  posts: SearchPost[]
  topicsPagination: PaginationMeta
  postsPagination: PaginationMeta
}>()

const q = ref(props.query)
const sectionSlug = ref(props.section || '')

watch(() => props.query, (value) => { q.value = value })
watch(() => props.section, (value) => { sectionSlug.value = value || '' })

function search() {
  router.get(routes.forumSearch, {
    q: q.value,
    section: sectionSlug.value || undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '搜索', current: true },
  ]" />

  <PageHeader title="搜索论坛" />

  <form class="mb-8 flex max-w-2xl flex-wrap gap-2" @submit.prevent="search">
    <Input v-model="q" placeholder="输入关键词..." class="min-w-[200px] flex-1" />
    <select v-model="sectionSlug" class="h-9 rounded-md border border-input bg-transparent px-2 text-sm">
      <option value="">全部分区</option>
      <option v-for="sec in sections" :key="sec.slug" :value="sec.slug">
        {{ sec.category ? `${sec.category} / ` : '' }}{{ sec.name }}
      </option>
    </select>
    <button type="submit" class="rounded-md bg-primary px-4 py-2 text-sm text-primary-foreground">搜索</button>
  </form>

  <template v-if="query">
    <h2 class="mb-3 text-sm font-semibold">主题</h2>
    <div v-if="topics.length" class="mb-8 rounded-lg border">
      <Table>
        <TableHeader><TableRow><TableHead>标题</TableHead><TableHead>最后回复</TableHead></TableRow></TableHeader>
        <TableBody>
          <TableRow v-for="topic in topics" :key="topic.id">
            <TableCell><Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link></TableCell>
            <TableCell>{{ topic.last_posted_at || '—' }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
      <Pagination :pagination="topicsPagination" :base-path="routes.forumSearch" query-param="topic_page" />
    </div>
    <p v-else class="mb-8 text-sm text-muted-foreground">未找到相关主题。</p>

    <h2 class="mb-3 text-sm font-semibold">帖子</h2>
    <div v-if="posts.length" class="rounded-lg border">
      <Table>
        <TableHeader><TableRow><TableHead>内容</TableHead><TableHead>主题</TableHead><TableHead>作者</TableHead></TableRow></TableHeader>
        <TableBody>
          <TableRow v-for="post in posts" :key="post.id">
            <TableCell>{{ post.body }}</TableCell>
            <TableCell><Link :href="post.topic_url" class="hover:underline">{{ post.topic_title }}</Link></TableCell>
            <TableCell>{{ post.author }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
      <Pagination :pagination="postsPagination" :base-path="routes.forumSearch" query-param="post_page" />
    </div>
    <p v-else class="text-sm text-muted-foreground">未找到相关帖子。</p>
  </template>
</template>
