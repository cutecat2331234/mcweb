<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import TopicTitleBadges from '@/components/portal/TopicTitleBadges.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  tab: 'posts' | 'topics' | 'following'
  posts: Array<{
    id: number
    floor_number: number
    author: string
    author_url: string
    body_excerpt: string
    topic_title: string
    topic_url: string
    section_name: string
    created_at: string
  }>
  topics: Array<{
    id: string
    title: string
    url: string
    author: string | null
    replies_count: number
    last_posted_at: string | null
    pinned: boolean
    locked: boolean
    prefix?: string | null
    has_unread: boolean
    unread_count: number
  }>
  pagination: PaginationMeta
  sort: string
  sortOptions: Array<{ value: string; label: string }>
}>()

function switchTab(value: 'posts' | 'topics' | 'following') {
  router.get(routes.forumActivity, { tab: value }, { preserveState: true })
}

function changeSort(value: string) {
  router.get(routes.forumActivity, { tab: 'topics', sort: value }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '动态', current: true },
  ]" />

  <PageHeader title="论坛动态" subtitle="全站最新活动" />

  <div class="mb-4 flex flex-wrap items-center gap-3">
    <div class="flex gap-2">
      <Button :variant="tab === 'posts' ? 'default' : 'outline'" size="sm" @click="switchTab('posts')">最新回复</Button>
      <Button :variant="tab === 'topics' ? 'default' : 'outline'" size="sm" @click="switchTab('topics')">最新主题</Button>
      <Button :variant="tab === 'following' ? 'default' : 'outline'" size="sm" @click="switchTab('following')">关注的人</Button>
    </div>
    <select
      v-if="tab === 'topics'"
      :value="sort"
      class="h-8 rounded-md border border-input bg-transparent px-2 text-sm"
      @change="changeSort(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="opt in sortOptions" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
    </select>
  </div>

  <div v-if="tab === 'posts' || tab === 'following'">
    <div v-if="posts.length" class="space-y-3">
      <article v-for="post in posts" :key="post.id" class="rounded-lg border p-4">
        <div class="mb-2 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
          <Link :href="post.author_url" class="font-medium text-foreground hover:underline">{{ post.author }}</Link>
          <span>·</span>
          <span>{{ post.created_at }}</span>
          <span>·</span>
          <span>{{ post.section_name }}</span>
        </div>
        <Link :href="post.topic_url" class="text-sm font-medium hover:underline">{{ post.topic_title }}</Link>
        <p class="mt-1 text-sm text-muted-foreground">#{{ post.floor_number }} {{ post.body_excerpt }}</p>
      </article>
    </div>
    <p v-else class="text-sm text-muted-foreground">暂无动态。</p>
  </div>

  <div v-else>
    <div v-if="topics.length" class="space-y-2">
      <Link
        v-for="topic in topics"
        :key="topic.id"
        :href="topic.url"
        class="block rounded-lg border p-4 transition-colors hover:bg-muted/50"
      >
        <div class="flex items-center gap-2">
          <TopicTitleBadges :pinned="topic.pinned" :locked="topic.locked" :prefix="topic.prefix" />
          <span class="font-medium">{{ topic.title }}</span>
          <Badge v-if="topic.has_unread" class="ml-auto">{{ topic.unread_count }} 未读</Badge>
        </div>
        <p class="mt-1 text-xs text-muted-foreground">
          {{ topic.author }} · {{ topic.replies_count }} 回复
          <span v-if="topic.last_posted_at"> · {{ topic.last_posted_at }}</span>
        </p>
      </Link>
    </div>
    <p v-else class="text-sm text-muted-foreground">暂无主题。</p>
  </div>

  <Pagination v-if="pagination.pages > 1" class="mt-6" :pagination="pagination" :base-path="routes.forumActivity" />
</template>
