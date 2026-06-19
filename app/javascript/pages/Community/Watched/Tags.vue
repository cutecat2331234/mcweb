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

defineProps<{
  tags: Array<{
    name: string
    slug: string
    description?: string | null
    url: string
    subscription_url: string
  }>
  tagTopicsUrl: string
  watchingOpmlUrl?: string | null
}>()

function unsubscribe(url: string) {
  router.patch(url, { level: 'off' }, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.watched.tagsBreadcrumb'), current: true },
  ]" />

  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
    <PageHeader :title="t('forum.watched.watchedTagsTitle')" :subtitle="t('forum.watched.watchedTagsSubtitle')" />
    <div class="flex flex-wrap items-center gap-2">
      <a
        v-if="watchingOpmlUrl"
        :href="watchingOpmlUrl"
        class="text-xs text-primary hover:underline"
        target="_blank"
        rel="noopener noreferrer"
      >
        {{ t('forum.watched.exportOpml') }}
      </a>
      <Button as-child variant="outline" size="sm">
        <Link :href="tagTopicsUrl">{{ t('forum.watched.tagTopicsFeed') }}</Link>
      </Button>
    </div>
  </div>

  <div v-if="tags.length" class="space-y-3">
    <div v-for="tag in tags" :key="tag.slug" class="flex items-start justify-between gap-3 rounded-lg border p-4">
      <div>
        <Link :href="tag.url" class="font-medium hover:underline">#{{ tag.name }}</Link>
        <p v-if="tag.description" class="mt-1 text-sm text-muted-foreground">{{ tag.description }}</p>
      </div>
      <Button type="button" variant="outline" size="sm" @click="unsubscribe(tag.subscription_url)">{{ t('forum.watched.unfollow') }}</Button>
    </div>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('forum.watched.emptyTagsHint') }}
  </p>
</template>
