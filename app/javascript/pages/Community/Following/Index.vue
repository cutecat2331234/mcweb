<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import TopicListTable, { type TopicListItem } from '@/components/portal/TopicListTable.vue'
import UserLink from '@/components/portal/UserLink.vue'
import Button from '@/components/ui/Button.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'
import type { CommunityRelationshipSnapshot } from '@/lib/communityRelationshipMutation'
import { useCommunityRelationshipList } from '@/lib/useCommunityRelationship'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  tab: 'topics' | 'users'
  users: Array<{
    username: string
    display_name: string | null
    forum_title: string | null
    avatar_url: string
    profile_url: string
    unfollow_url: string
    relationship: CommunityRelationshipSnapshot
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

const { states, visibleUsers, remove } = useCommunityRelationshipList(
  () => props.users, () => router.reload({ preserveScroll: true }),
)
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.following.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.following.title')" />

  <div class="mb-4 flex flex-wrap items-center gap-3">
    <div class="flex gap-2">
      <Button :variant="tab === 'topics' ? 'default' : 'outline'" size="sm" @click="switchTab('topics')">{{ t('forum.following.tabTopics') }}</Button>
      <Button :variant="tab === 'users' ? 'default' : 'outline'" size="sm" @click="switchTab('users')">{{ t('forum.following.tabUsers') }}</Button>
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
    <p v-else class="text-sm text-muted-foreground">{{ t('forum.following.emptyTopics') }}</p>
    <Pagination
      v-if="topicsPagination.pages > 1"
      :pagination="topicsPagination"
      :base-path="routes.forumFollowing"
      page-param="topics_page"
    />
  </section>

  <section v-else>
    <div v-if="visibleUsers.length" class="space-y-3">
      <div v-for="user in visibleUsers" :key="user.username" class="flex items-center gap-3 rounded-lg border p-4">
        <UserLink variant="avatar" size="lg" :user="user" />
        <div class="min-w-0 flex-1">
          <UserLink variant="name" :user="user" link-class="font-medium hover:underline" />
          <p v-if="user.forum_title" class="text-xs text-muted-foreground">{{ user.forum_title }}</p>
          <p v-if="states.get(user.username)?.error" role="status" class="text-sm text-muted-foreground">{{ t(`components.relationship.errors.${states.get(user.username)?.error}`) }}</p>
        </div>
        <Button type="button" size="sm" variant="outline" :disabled="states.get(user.username)?.processing || !states.get(user.username)?.revision" @click="remove(user, user.unfollow_url)">{{ states.get(user.username)?.error === 'retry' ? t('components.relationship.retry') : t('forum.following.unfollow') }}</Button>
      </div>
    </div>
    <p v-else class="text-sm text-muted-foreground">{{ t('forum.following.emptyUsers') }}</p>
    <Pagination
      v-if="usersPagination.pages > 1"
      :pagination="usersPagination"
      :base-path="routes.forumFollowing"
      page-param="users_page"
    />
  </section>
</template>
