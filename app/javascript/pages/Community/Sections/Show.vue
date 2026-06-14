<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import TopicTitleBadges from '@/components/portal/TopicTitleBadges.vue'
import Badge from '@/components/ui/Badge.vue'
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
  views_count: number
  last_posted_at: string | null
  pinned: boolean
  locked: boolean
  featured: boolean
  solved?: boolean
  prefix?: string | null
  unread_count: number
  has_unread: boolean
  participant_avatars?: Array<{ username: string; avatar_url: string; profile_url: string }>
}

const props = defineProps<{
  section: {
    name: string
    slug: string
    description: string | null
    new_topic_url: string | null
    watching: boolean
    muted?: boolean
    subscription_url: string
    mute_url?: string | null
    mark_all_read_url?: string | null
    rss_url: string
  }
  featuredTopics: TopicItem[]
  topics: TopicItem[]
  pagination: PaginationMeta
  sort: string
  filter: string
  filterOptions: Array<{ value: string; label: string }>
  canCreateTopic: boolean
}>()

const sortOptions = [
  { value: 'activity', label: '最近活跃' },
  { value: 'hot', label: '热门' },
  { value: 'newest', label: '最新发布' },
  { value: 'replies', label: '最多回复' },
  { value: 'views', label: '最多浏览' },
]

function changeSort(value: string) {
  router.get(routes.forumSection(props.section.slug), { sort: value, filter: props.filter || undefined }, { preserveState: true })
}

function changeFilter(value: string) {
  router.get(routes.forumSection(props.section.slug), { sort: props.sort, filter: value || undefined }, { preserveState: true })
}

function toggleWatch() {
  router.post(props.section.subscription_url, {}, { preserveScroll: true })
}
function toggleMute() {
  if (!props.section.mute_url) return
  router.post(props.section.mute_url, {}, { preserveScroll: true })
}
function markAllRead() {
  if (!props.section.mark_all_read_url) return
  router.patch(props.section.mark_all_read_url)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: section.name, current: true },
  ]" />

  <div class="mb-6 flex flex-wrap items-start justify-between gap-4">
    <PageHeader :title="section.name" :subtitle="section.description || undefined" />
    <div class="flex flex-wrap gap-2">
      <Button type="button" variant="outline" size="sm" @click="toggleWatch">
        {{ section.watching ? '取消关注分区' : '关注分区' }}
      </Button>
      <Button v-if="section.mute_url" type="button" variant="outline" size="sm" @click="toggleMute">
        {{ section.muted ? '取消静音分区' : '静音分区' }}
      </Button>
      <Button v-if="section.mark_all_read_url" type="button" variant="outline" size="sm" @click="markAllRead">
        全部标为已读
      </Button>
      <Button v-if="canCreateTopic && section.new_topic_url" as-child>
        <Link :href="section.new_topic_url">新建主题</Link>
      </Button>
      <Button as-child variant="outline" size="sm">
        <a :href="section.rss_url" target="_blank" rel="noopener">RSS</a>
      </Button>
    </div>
  </div>

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
  </div>

  <div v-if="featuredTopics.length" class="mb-6">
    <h2 class="mb-2 text-sm font-semibold">精选主题</h2>
    <div class="space-y-2 rounded-lg border p-3">
      <div v-for="topic in featuredTopics" :key="topic.id" class="flex items-center gap-2 text-sm">
        <Badge variant="secondary">精选</Badge>
        <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
      </div>
    </div>
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
            />
            <Link :href="topic.url" class="font-medium hover:underline">{{ topic.title }}</Link>
            <div v-if="topic.participant_avatars?.length" class="mt-1 flex items-center gap-1">
              <img
                v-for="avatar in topic.participant_avatars"
                :key="avatar.username"
                :src="avatar.avatar_url"
                :alt="avatar.username"
                :title="avatar.username"
                class="h-5 w-5 rounded-full border"
              />
            </div>
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
