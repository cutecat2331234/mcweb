<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
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
    unread_count: number
  }>
  markAllReadUrl: string
}>()

function markAllRead() {
  router.patch(props.markAllReadUrl)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '未读主题', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader title="未读主题" subtitle="你有未读回复的主题" />
    <Button v-if="topics.length" type="button" variant="outline" size="sm" @click="markAllRead">
      全部标为已读
    </Button>
  </div>

  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>主题</TableHead>
          <TableHead>作者</TableHead>
          <TableHead>未读</TableHead>
          <TableHead>最后回复</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell>
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
          </TableCell>
          <TableCell>{{ topic.author || '—' }}</TableCell>
          <TableCell><Badge>{{ topic.unread_count }}</Badge></TableCell>
          <TableCell>{{ topic.last_posted_at || '—' }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    没有未读主题，全部已读。
  </p>
</template>
