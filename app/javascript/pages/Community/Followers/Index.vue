<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
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
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: profile.display_name || profile.username, href: profile.profile_url },
    { label: '粉丝', current: true },
  ]" />

  <PageHeader
    :title="`${profile.display_name || profile.username} 的粉丝`"
    :subtitle="`共 ${profile.followers_count} 人`"
  />

  <div v-if="followers.length" class="space-y-3">
    <div v-for="follower in followers" :key="follower.username" class="flex items-center gap-3 rounded-lg border p-4">
      <img :src="follower.avatar_url" :alt="follower.username" class="h-10 w-10 rounded-full" />
      <div class="min-w-0 flex-1">
        <Link :href="follower.profile_url" class="font-medium hover:underline">
          {{ follower.display_name || follower.username }}
        </Link>
        <p v-if="follower.forum_title" class="text-xs text-muted-foreground">{{ follower.forum_title }}</p>
      </div>
      <span class="text-xs text-muted-foreground">关注于 {{ follower.followed_at }}</span>
    </div>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无粉丝。</p>

  <Pagination
    v-if="pagination.pages > 1"
    :pagination="pagination"
    :base-path="routes.forumUserFollowers(profile.username)"
  />
</template>
