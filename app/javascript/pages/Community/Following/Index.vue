<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  tab: 'topics' | 'users'
  users: Array<{
    username: string
    display_name: string | null
    forum_title: string | null
    avatar_url: string
    profile_url: string
    unfollow_url: string
  }>
  usersPagination: PaginationMeta
  topics: TopicListItem[]
  topicsPagination: PaginationMeta
  sort: string
  sortOptions: Array<{ value: string; label: string }>
}>()

function switchTab(value: 'topics' | 'users') {
  router.get(routes.forumFollowing, { tab: value, sort: props.sort || undefined }, { preserveState: true })
}

function changeSort(value: string) {
  router.get(routes.forumFollowing, { tab: props.tab, sort: value }, { preserveState: true })
}

function unfollow(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '我的关注', current: true },
  ]" />

  <PageHeader title="我的关注" subtitle="关注用户与其最新主题" />

  <div class="mb-4 flex flex-wrap items-center gap-3">
    <div class="flex gap-2">
      <Button :variant="tab === 'topics' ? 'default' : 'outline'" size="sm" @click="switchTab('topics')">主题动态</Button>
      <Button :variant="tab === 'users' ? 'default' : 'outline'" size="sm" @click="switchTab('users')">关注用户</Button>
    </div>
    <Select
      v-if="tab === 'topics'"
      :model-value="sort"
      :options="sortOptions"
      size="sm"
      @update:model-value="changeSort"
    />
  </div>

  <section v-if="tab === 'topics'">
    <TopicListTable v-if="topics.length" :topics="topics" show-views show-participants />
    <p v-else class="text-sm text-muted-foreground">关注用户暂无新主题。</p>
    <Pagination
      v-if="topicsPagination.pages > 1"
      :pagination="topicsPagination"
      :base-path="routes.forumFollowing"
      page-param="topics_page"
    />
  </section>

  <section v-else>
    <div v-if="users.length" class="space-y-3">
      <div v-for="user in users" :key="user.username" class="flex items-center gap-3 rounded-lg border p-4">
        <img :src="user.avatar_url" :alt="user.username" class="h-10 w-10 rounded-full" />
        <div class="min-w-0 flex-1">
          <Link :href="user.profile_url" class="font-medium hover:underline">
            {{ user.display_name || user.username }}
          </Link>
          <p v-if="user.forum_title" class="text-xs text-muted-foreground">{{ user.forum_title }}</p>
        </div>
        <Button type="button" size="sm" variant="outline" @click="unfollow(user.unfollow_url)">取消关注</Button>
      </div>
    </div>
    <p v-else class="text-sm text-muted-foreground">尚未关注任何用户。</p>
    <Pagination
      v-if="usersPagination.pages > 1"
      :pagination="usersPagination"
      :base-path="routes.forumFollowing"
      page-param="users_page"
    />
  </section>
</template>
