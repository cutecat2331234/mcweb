<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
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
    has_unread: boolean
    unread_count: number
  }>
  pagination: PaginationMeta
  sort: string
  rss_url: string
}>()

const sortOptions = [
  { value: 'activity', label: '最近活跃' },
  { value: 'newest', label: '最新发布' },
  { value: 'replies', label: '最多回复' },
  { value: 'views', label: '最多浏览' },
]

function changeSort(value: string) {
  router.get(routes.forumLatest, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '最新', current: true },
  ]" />

  <PageHeader title="最新主题" subtitle="全站最近活跃的主题" />

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <label class="text-sm text-muted-foreground">排序：</label>
    <select
      :value="sort"
      class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
      @change="changeSort(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
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
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
            <Badge v-if="topic.has_unread" class="ml-2">{{ topic.unread_count }} 未读</Badge>
          </TableCell>
          <TableCell>{{ topic.author || '—' }}</TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
          <TableCell>{{ topic.last_posted_at || '—' }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无主题。
  </p>

  <Pagination :pagination="pagination" :base-path="routes.forumLatest" />
</template>
