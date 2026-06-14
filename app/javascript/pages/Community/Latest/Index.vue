<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicTitleBadges from '@/components/portal/TopicTitleBadges.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  topics: Array<{
    id: string
    title: string
    url: string
    author: string | null
    replies_count: number
    last_posted_at: string | null
    last_poster_username?: string | null
    last_poster_url?: string | null
    linked_product?: boolean
    linked_product_url?: string | null
    tags?: Array<{ name: string; slug: string; url: string }>
    has_unread: boolean
    unread_count: number
    pinned?: boolean
    featured?: boolean
    locked?: boolean
    solved?: boolean
    prefix?: string | null
  }>
  pagination: PaginationMeta
  sort: string
  filter: string
  filterOptions: Array<{ value: string; label: string }>
  rss_url: string
}>()

const sortOptions = [
  { value: 'activity', label: '最近活跃' },
  { value: 'hot', label: '热门' },
  { value: 'newest', label: '最新发布' },
  { value: 'replies', label: '最多回复' },
  { value: 'views', label: '最多浏览' },
]

function changeSort(value: string) {
  router.get(routes.forumLatest, { sort: value, filter: props.filter || undefined }, { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumLatest, { sort: props.sort, filter: value || undefined }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '最新', current: true },
  ]" />

  <PageHeader title="最新主题" subtitle="全站最近活跃的主题" />

  <div class="mb-4 flex flex-wrap items-center gap-4">
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">排序：</label>
      <select
        :value="sort"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeSort(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
    </div>
    <div class="flex items-center gap-2">
      <label class="text-sm text-muted-foreground">筛选：</label>
      <select
        :value="filter"
        class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
        @change="changeFilter(($event.target as HTMLSelectElement).value)"
      >
        <option v-for="opt in filterOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
    </div>
    <a :href="rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">RSS 订阅</a>
  </div>

  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>主题</TableHead>
          <TableHead>作者</TableHead>
          <TableHead>回复</TableHead>
          <TableHead>最后回复</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell>
            <TopicTitleBadges
              :prefix="topic.prefix"
              :pinned="topic.pinned"
              :featured="topic.featured"
              :locked="topic.locked"
              :solved="topic.solved"
              :has-unread="topic.has_unread"
              :unread-count="topic.unread_count"
              :linked-product="topic.linked_product"
              :linked-product-url="topic.linked_product_url"
              :tags="topic.tags"
            />
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
          </TableCell>
          <TableCell>{{ topic.author || '—' }}</TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
          <TableCell>
            <template v-if="topic.last_poster_username && topic.last_poster_url">
              <Link :href="topic.last_poster_url" class="hover:underline">@{{ topic.last_poster_username }}</Link>
            </template>
            <span v-else>{{ topic.last_posted_at || '—' }}</span>
            <p v-if="topic.last_poster_username" class="text-xs text-muted-foreground">{{ topic.last_posted_at || '—' }}</p>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无主题。
  </p>

  <Pagination :pagination="pagination" :base-path="routes.forumLatest" />
</template>
