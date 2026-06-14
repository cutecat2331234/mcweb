<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  profile: {
    username: string
    avatar_url: string
    member_since: string
    topics_count: number
    posts_count: number
    profile_url: string
    message_url: string | null
    block_url: string | null
    is_blocked: boolean
    is_muted: boolean
  }
  topics: Array<{
    id: string
    title: string
    url: string
    replies_count: number
    last_posted_at: string | null
  }>
  recent_posts: Array<{
    id: number
    body: string
    floor_number: number
    topic_title: string
    topic_url: string
    created_at: string
  }>
}>()

function toggleBlock() {
  if (!props.profile.block_url) return
  router.post(props.profile.block_url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: profile.username, current: true },
  ]" />

  <p v-if="profile.is_muted" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    你当前被禁言，暂时无法发帖。
  </p>

  <div class="mb-6 flex items-center gap-4">
    <img :src="profile.avatar_url" :alt="profile.username" class="h-16 w-16 rounded-full" />
    <div>
      <PageHeader :title="profile.username" :subtitle="`加入于 ${profile.member_since}`" />
      <div class="mt-2 flex gap-6 text-sm">
        <span><strong>{{ profile.topics_count }}</strong> 主题</span>
        <span><strong>{{ profile.posts_count }}</strong> 帖子</span>
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <Button v-if="profile.message_url" as-child size="sm">
          <Link :href="profile.message_url">发私信</Link>
        </Button>
        <Button
          v-if="profile.block_url"
          type="button"
          size="sm"
          :variant="profile.is_blocked ? 'outline' : 'destructive'"
          @click="toggleBlock"
        >
          {{ profile.is_blocked ? '取消拉黑' : '拉黑用户' }}
        </Button>
      </div>
    </div>
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

  <h2 class="mb-3 mt-8 text-sm font-semibold">最近回复</h2>
  <div v-if="recent_posts.length" class="space-y-2 rounded-lg border p-4">
    <div v-for="post in recent_posts" :key="post.id" class="text-sm">
      <Link :href="post.topic_url" class="font-medium hover:underline">#{{ post.floor_number }} {{ post.topic_title }}</Link>
      <p class="text-muted-foreground">{{ post.body }}</p>
      <p class="text-xs text-muted-foreground">{{ post.created_at }}</p>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无回复。</p>
</template>
