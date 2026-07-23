<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import UserLink from '@/components/portal/UserLink.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  profile: {
    username: string
    display_name: string | null
    profile_url: string
    followers_count: number
  }
  followers: Array<{
    username: string
    display_name: string | null
    forum_title: string | null
    avatar_url: string
    profile_url: string
    followed_at: string
  }>
  pagination: PaginationMeta
}>()

const displayName = computed(() => props.profile.display_name || props.profile.username)
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: displayName, href: profile.profile_url },
    { label: t('forum.followers.breadcrumb'), current: true },
  ]" />

  <PageHeader
    :title="t('forum.followers.title', { name: displayName })"
    :subtitle="t('forum.followers.subtitle', { count: profile.followers_count })"
  />

  <div v-if="followers.length" class="space-y-3">
    <div v-for="follower in followers" :key="follower.username" class="flex items-center gap-3 rounded-lg border p-4">
      <UserLink variant="avatar" size="lg" :user="follower" />
      <div class="min-w-0 flex-1">
        <UserLink variant="name" :user="follower" link-class="font-medium hover:underline" />
        <p v-if="follower.forum_title" class="text-xs text-muted-foreground">{{ follower.forum_title }}</p>
      </div>
      <span class="text-xs text-muted-foreground">{{ t('forum.followers.followedAt', { at: follower.followed_at }) }}</span>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.followers.empty') }}</p>

  <Pagination
    v-if="pagination.pages > 1"
    :pagination="pagination"
    :base-path="routes.forumUserFollowers(profile.username)"
  />
</template>
