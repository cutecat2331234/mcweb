<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export interface SectionItem {
  id: number
  name: string
  slug: string
  description: string | null
  category_name: string | null
  category_icon?: string | null
  category_color_hex?: string | null
  color_hex?: string | null
  icon?: string | null
  topics_count: number
  unread_count?: number
  last_post?: {
    topic_title: string
    topic_url: string
    author: string | null
    author_url: string | null
    at: string | null
  } | null
  url: string
  children?: SectionItem[]
}

const props = defineProps<{
  sections: SectionItem[]
  categories?: Array<{
    slug: string
    name: string
    description: string | null
    icon: string | null
    color_hex: string | null
  }>
  pagination: PaginationMeta
  forumStats?: {
    topics: number
    posts: number
    members: number
    online: number
    latest_member: { username: string; display_name: string | null; url: string } | null
  }
  latestThreads?: Array<{ title: string; url: string; author: string | null; at: string | null; replies: number }>
  markAllReadUrl?: string | null
}>()

function markAllRead() {
  if (!props.markAllReadUrl) return
  router.patch(props.markAllReadUrl, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-2">
    <PageHeader :title="t('forum.sectionsIndex.title')" :subtitle="t('forum.sectionsIndex.subtitle')" />
    <Button v-if="markAllReadUrl" variant="outline" size="sm" @click="markAllRead">{{ t('forum.sectionsIndex.markAllRead') }}</Button>
  </div>

  <div v-if="categories?.length" class="mb-6 grid gap-3 sm:grid-cols-2">
    <div
      v-for="category in categories"
      :key="category.slug"
      class="rounded-lg border p-4"
    >
      <div class="flex items-center gap-2 font-medium">
        <span v-if="category.icon">{{ category.icon }}</span>
        <span
          v-if="category.color_hex"
          class="inline-block h-2.5 w-2.5 rounded-full"
          :style="{ backgroundColor: category.color_hex }"
        />
        {{ category.name }}
      </div>
      <p v-if="category.description" class="mt-1 text-sm text-muted-foreground">{{ category.description }}</p>
    </div>
  </div>

  <div v-if="sections.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('forum.sectionsIndex.colSection') }}</TableHead>
          <TableHead>{{ t('forum.sectionsIndex.colCategory') }}</TableHead>
          <TableHead>{{ t('forum.sectionsIndex.colTopics') }}</TableHead>
          <TableHead>{{ t('forum.sectionsIndex.colUnread') }}</TableHead>
          <TableHead>{{ t('forum.sectionsIndex.colLastPost') }}</TableHead>
          <TableHead>{{ t('forum.sectionsIndex.colDescription') }}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <template v-for="section in sections" :key="section.id">
          <TableRow>
            <TableCell>
              <Link :href="section.url" class="font-medium hover:underline">
                <span v-if="section.icon" class="mr-1">{{ section.icon }}</span>
                <span
                  v-if="section.color_hex"
                  class="mr-2 inline-block h-2.5 w-2.5 rounded-full align-middle"
                  :style="{ backgroundColor: section.color_hex }"
                />
                {{ section.name }}
              </Link>
              <span class="ml-2 text-xs text-muted-foreground">{{ section.slug }}</span>
            </TableCell>
            <TableCell>
              <span v-if="section.category_icon" class="mr-1">{{ section.category_icon }}</span>
              <span
                v-if="section.category_color_hex"
                class="mr-1 inline-block h-2 w-2 rounded-full align-middle"
                :style="{ backgroundColor: section.category_color_hex }"
              />
              {{ section.category_name || '—' }}
            </TableCell>
            <TableCell>{{ section.topics_count }}</TableCell>
            <TableCell>
              <span v-if="section.unread_count" class="text-xs font-medium text-primary">{{ section.unread_count }}</span>
              <span v-else class="text-muted-foreground">—</span>
            </TableCell>
            <TableCell class="max-w-[12rem] text-xs">
              <template v-if="section.last_post">
                <Link :href="section.last_post.topic_url" class="block truncate font-medium hover:underline">{{ section.last_post.topic_title }}</Link>
                <span class="text-muted-foreground">
                  <Link v-if="section.last_post.author_url" :href="section.last_post.author_url" class="hover:underline">{{ section.last_post.author }}</Link>
                  <span v-if="section.last_post.at"> · {{ section.last_post.at }}</span>
                </span>
              </template>
              <span v-else class="text-muted-foreground">—</span>
            </TableCell>
            <TableCell class="text-muted-foreground">
              {{ section.description || '—' }}
            </TableCell>
          </TableRow>
          <TableRow v-for="child in section.children || []" :key="child.id">
            <TableCell class="pl-8">
              <span class="text-muted-foreground">↳ </span>
              <Link :href="child.url" class="font-medium hover:underline">
                {{ child.name }}
              </Link>
            </TableCell>
            <TableCell>{{ child.category_name || section.category_name || '—' }}</TableCell>
            <TableCell>{{ child.topics_count }}</TableCell>
            <TableCell>
              <span v-if="child.unread_count" class="text-xs font-medium text-primary">{{ child.unread_count }}</span>
              <span v-else class="text-muted-foreground">—</span>
            </TableCell>
            <TableCell class="max-w-[12rem] text-xs">
              <template v-if="child.last_post">
                <Link :href="child.last_post.topic_url" class="block truncate font-medium hover:underline">{{ child.last_post.topic_title }}</Link>
                <span class="text-muted-foreground">
                  <Link v-if="child.last_post.author_url" :href="child.last_post.author_url" class="hover:underline">{{ child.last_post.author }}</Link>
                  <span v-if="child.last_post.at"> · {{ child.last_post.at }}</span>
                </span>
              </template>
              <span v-else class="text-muted-foreground">—</span>
            </TableCell>
            <TableCell class="text-muted-foreground">
              {{ child.description || '—' }}
            </TableCell>
          </TableRow>
        </template>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('forum.sectionsIndex.empty') }}
  </p>

  <Pagination :pagination="pagination" :base-path="routes.forum" />

  <div v-if="latestThreads?.length" class="mt-8 rounded-lg border p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.sectionsIndex.latestThreads') }}</h2>
    <ul class="space-y-2">
      <li v-for="thread in latestThreads" :key="thread.url" class="flex flex-wrap items-baseline justify-between gap-x-3 text-sm">
        <Link :href="thread.url" class="min-w-0 flex-1 truncate font-medium hover:underline">{{ thread.title }}</Link>
        <span class="text-xs text-muted-foreground">
          <span v-if="thread.author">{{ thread.author }}</span>
          <span v-if="thread.at"> · {{ thread.at }}</span>
          · {{ t('forum.sectionsIndex.replyCount', { n: thread.replies }) }}
        </span>
      </li>
    </ul>
  </div>

  <div v-if="forumStats" class="mt-8 rounded-lg border bg-muted/20 p-4">
    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.sectionsIndex.statsTitle') }}</h2>
    <div class="flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted-foreground">
      <span><strong class="text-foreground">{{ forumStats.topics }}</strong> {{ t('forum.sectionsIndex.statTopics') }}</span>
      <span><strong class="text-foreground">{{ forumStats.posts }}</strong> {{ t('forum.sectionsIndex.statPosts') }}</span>
      <span><strong class="text-foreground">{{ forumStats.members }}</strong> {{ t('forum.sectionsIndex.statMembers') }}</span>
      <span><strong class="text-foreground">{{ forumStats.online }}</strong> {{ t('forum.sectionsIndex.statOnline') }}</span>
      <span v-if="forumStats.latest_member">
        {{ t('forum.sectionsIndex.statLatest') }}
        <Link :href="forumStats.latest_member.url" class="text-primary hover:underline">{{ forumStats.latest_member.display_name || forumStats.latest_member.username }}</Link>
      </span>
    </div>
  </div>
</template>
