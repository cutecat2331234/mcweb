<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface TopicItem {
  id: string
  title: string
  url: string
  author: string | null
  replies_count: number
  last_posted_at: string | null
  pinned: boolean
  locked: boolean
}

export interface SectionDetail {
  name: string
  slug: string
  description: string | null
  new_topic_url: string | null
}

defineProps<{
  section: SectionDetail
  topics: TopicItem[]
  pagination: PaginationMeta
  canCreateTopic: boolean
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: section.name, current: true },
  ]" />

  <div class="mb-6 flex items-start justify-between gap-4">
    <PageHeader :title="section.name" :subtitle="section.description || undefined" />
    <Button v-if="canCreateTopic && section.new_topic_url" as-child>
      <Link :href="section.new_topic_url">新建主题</Link>
    </Button>
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
            <span v-if="topic.pinned" class="mr-1 text-xs text-muted-foreground">[置顶]</span>
            <span v-if="topic.locked" class="mr-1 text-xs text-muted-foreground">[锁定]</span>
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
          </TableCell>
          <TableCell>{{ topic.author || '—' }}</TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
          <TableCell>{{ topic.last_posted_at || '—' }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    此分区暂无主题。
  </p>

  <Pagination :pagination="pagination" :base-path="routes.forumSection(section.slug)" />
</template>
