<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

defineProps<{
  posts: Array<{
    id: number
    floor_number: number
    author: string
    author_url: string
    body_excerpt: string
    body_html: string
    topic_title: string
    topic_url: string
    section_name: string
    created_at: string
  }>
  pagination: PaginationMeta
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '动态', current: true },
  ]" />

  <PageHeader title="论坛动态" subtitle="全站最新回复" />

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

  <Pagination v-if="posts.length" class="mt-6" :pagination="pagination" :base-path="routes.forumActivity" />
</template>
