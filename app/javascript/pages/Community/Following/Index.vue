<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  users: Array<{
    username: string
    display_name: string | null
    forum_title: string | null
    avatar_url: string
    profile_url: string
    unfollow_url: string
  }>
  topics: Array<{
    id: string
    title: string
    url: string
    author: string | null
    last_posted_at: string | null
    replies_count: number
  }>
}>()

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

  <section v-if="topics.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">关注用户的主题</h2>
    <div class="space-y-2">
      <Link
        v-for="topic in topics"
        :key="topic.id"
        :href="topic.url"
        class="block rounded-lg border p-4 transition-colors hover:bg-muted/50"
      >
        <p class="font-medium">{{ topic.title }}</p>
        <p class="mt-1 text-xs text-muted-foreground">
          {{ topic.author }} · {{ topic.replies_count }} 回复
          <span v-if="topic.last_posted_at"> · {{ topic.last_posted_at }}</span>
        </p>
      </Link>
    </div>
  </section>

  <section>
    <h2 class="mb-3 text-sm font-semibold">关注的用户</h2>
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
  </section>
</template>
