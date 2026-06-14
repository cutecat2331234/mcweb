<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
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
  tag: {
    name: string
    slug: string
    description?: string | null
    rss_url: string
    watching?: boolean
    subscription_url?: string
  }
  topics: Array<{
    id: string
    title: string
    url: string
    author: string | null
    replies_count: number
    has_unread: boolean
    unread_count: number
  }>
  pagination: PaginationMeta
  loggedIn?: boolean
}>()

function toggleWatch() {
  if (!props.tag.subscription_url) return
  router.post(props.tag.subscription_url)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: `标签：${tag.name}`, current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
    <PageHeader :title="`#${tag.name}`" subtitle="按标签浏览主题" />
    <Button v-if="loggedIn && tag.subscription_url" type="button" variant="outline" size="sm" @click="toggleWatch">
      {{ tag.watching ? '取消关注标签' : '关注此标签' }}
    </Button>
  </div>

  <p v-if="tag.description" class="mb-4 text-sm text-muted-foreground">{{ tag.description }}</p>

  <p class="mb-4">
    <a :href="tag.rss_url" target="_blank" rel="noopener" class="text-sm text-muted-foreground hover:text-foreground">RSS 订阅</a>
  </p>

  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>主题</TableHead>
          <TableHead>作者</TableHead>
          <TableHead>回复</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell>
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
            <Badge v-if="topic.has_unread" class="ml-2">{{ topic.unread_count }}</Badge>
          </TableCell>
          <TableCell>{{ topic.author || '—' }}</TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">此标签下暂无主题。</p>

  <Pagination :pagination="pagination" :base-path="`/forum/tags/${tag.slug}`" />
</template>
