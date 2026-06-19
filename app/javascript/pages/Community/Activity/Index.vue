<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

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
  topics: TopicListItem[]
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
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.activity.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.activity.title')" :subtitle="t('forum.activity.subtitle')" />

  <div class="mb-4 flex flex-wrap items-center gap-3">
    <div class="flex gap-2">
      <Button :variant="tab === 'posts' ? 'default' : 'outline'" size="sm" @click="switchTab('posts')">{{ t('forum.activity.tabPosts') }}</Button>
      <Button :variant="tab === 'topics' ? 'default' : 'outline'" size="sm" @click="switchTab('topics')">{{ t('forum.activity.tabTopics') }}</Button>
      <Button :variant="tab === 'following' ? 'default' : 'outline'" size="sm" @click="switchTab('following')">{{ t('forum.activity.tabFollowing') }}</Button>
    </div>
    <Select
      v-if="tab === 'topics'"
      :model-value="sort"
      :options="sortOptions"
      size="sm"
      @update:model-value="changeSort"
    />
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
    <p v-else class="text-sm text-muted-foreground">{{ t('forum.activity.emptyPosts') }}</p>
  </div>

  <div v-else>
    <TopicListTable v-if="topics.length" :topics="topics" show-views show-participants />
    <p v-else class="text-sm text-muted-foreground">{{ t('forum.activity.emptyTopics') }}</p>
  </div>

  <Pagination v-if="pagination.pages > 1" class="mt-6" :pagination="pagination" :base-path="routes.forumActivity" />
</template>
