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
  sortOptions: Array<{ value: string; label: string }>
}>()

function changeSort(value: string) {
  router.get(routes.forumWatchedTagTopics, { sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '关注标签', href: routes.forumWatchedTags },
    { label: '标签主题', current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader title="关注标签的主题" subtitle="来自你关注标签的最新主题" />
    <select
      :value="sort"
      class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
      @change="changeSort(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
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
    关注标签后，使用这些标签的新主题会显示在这里。
  </p>
  <Pagination v-if="pagination.pages > 1" :pagination="pagination" :base-path="routes.forumWatchedTagTopics" />
</template>
