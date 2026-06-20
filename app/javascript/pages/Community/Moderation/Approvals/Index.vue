<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

export interface PendingPostItem {
  id: number
  author: string
  topic_title: string
  topic_url: string
  section_name: string
  excerpt: string
  created_at: string
  attachments?: Array<{ filename: string; human_size: string; download_url: string }>
  approve_url: string
  reject_url: string
}

defineProps<{
  posts: PendingPostItem[]
}>()

function approve(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function reject(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.moderation.approvalsTitle'), current: true },
  ]" />

  <PageHeader :title="t('forum.moderation.approvalsTitle')" :subtitle="t('forum.moderation.approvalsSubtitle')" />

  <p v-if="posts.length === 0" class="text-sm text-muted-foreground">{{ t('forum.moderation.noPendingPosts') }}</p>

  <ul v-else class="space-y-3">
    <li v-for="post in posts" :key="post.id" class="rounded-lg border p-4">
      <div class="flex flex-wrap items-start justify-between gap-2">
        <div class="min-w-0 space-y-1">
          <p class="text-sm text-muted-foreground">
            {{ post.section_name }} · {{ post.author }} · {{ post.created_at }}
          </p>
          <Link :href="post.topic_url" class="font-medium hover:underline">{{ post.topic_title }}</Link>
          <p class="text-sm text-muted-foreground whitespace-pre-wrap">{{ post.excerpt }}</p>
          <ul v-if="post.attachments?.length" class="mt-1 space-y-0.5 text-xs text-muted-foreground">
            <li v-for="attachment in post.attachments" :key="attachment.download_url">
              <a :href="attachment.download_url" class="hover:underline">{{ attachment.filename }}</a>
              <span> ({{ attachment.human_size }})</span>
            </li>
          </ul>
        </div>
        <div class="flex shrink-0 gap-2">
          <Button type="button" size="sm" @click="approve(post.approve_url)">{{ t('forum.moderation.approve') }}</Button>
          <Button type="button" size="sm" variant="outline" @click="reject(post.reject_url)">{{ t('forum.moderation.reject') }}</Button>
        </div>
      </div>
    </li>
  </ul>
</template>
