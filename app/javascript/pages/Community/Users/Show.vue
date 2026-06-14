<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  profile: {
    username: string
    member_since: string
    topics_count: number
    posts_count: number
    profile_url: string
  }
  topics: Array<{
    id: string
    title: string
    url: string
    replies_count: number
    last_posted_at: string | null
  }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: profile.username, current: true },
  ]" />

  <PageHeader :title="profile.username" :subtitle="`加入于 ${profile.member_since}`" />

  <div class="mb-6 flex gap-6 text-sm">
    <span><strong>{{ profile.topics_count }}</strong> 主题</span>
    <span><strong>{{ profile.posts_count }}</strong> 帖子</span>
  </div>

  <h2 class="mb-3 text-sm font-semibold">最近主题</h2>
  <div v-if="topics.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>标题</TableHead>
          <TableHead>回复</TableHead>
          <TableHead>最后回复</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="topic in topics" :key="topic.id">
          <TableCell><Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link></TableCell>
          <TableCell>{{ topic.replies_count }}</TableCell>
          <TableCell>{{ topic.last_posted_at || '—' }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无主题。</p>
</template>
