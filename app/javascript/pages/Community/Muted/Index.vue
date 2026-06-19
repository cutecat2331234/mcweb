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
  topicMutes: Array<{
    id: number
    title: string
    topic_url: string
    section_name: string
    muted_at: string
    unmute_url: string
  }>
  sectionMutes: Array<{
    id: number
    name: string
    section_url: string
    muted_at: string
    unmute_url: string
  }>
}>()

function unmute(url: string) {
  router.post(url, {}, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.muted.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.muted.title')" :subtitle="t('forum.muted.subtitle')" />

  <section v-if="topicMutes.length" class="mb-8">
    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.muted.topicMutes') }}</h2>
    <div class="divide-y rounded-lg border">
      <div v-for="item in topicMutes" :key="item.id" class="flex items-center justify-between gap-4 p-4">
        <div>
          <Link :href="item.topic_url" class="font-medium hover:underline">{{ item.title }}</Link>
          <p class="text-xs text-muted-foreground">{{ t('forum.muted.topicMutedMeta', { section: item.section_name, at: item.muted_at }) }}</p>
        </div>
        <Button type="button" variant="outline" size="sm" @click="unmute(item.unmute_url)">{{ t('forum.muted.unmute') }}</Button>
      </div>
    </div>
  </section>

  <section v-if="sectionMutes.length">
    <h2 class="mb-3 text-sm font-semibold">{{ t('forum.muted.sectionMutes') }}</h2>
    <div class="divide-y rounded-lg border">
      <div v-for="item in sectionMutes" :key="item.id" class="flex items-center justify-between gap-4 p-4">
        <div>
          <Link :href="item.section_url" class="font-medium hover:underline">{{ item.name }}</Link>
          <p class="text-xs text-muted-foreground">{{ t('forum.muted.mutedAt', { at: item.muted_at }) }}</p>
        </div>
        <Button type="button" variant="outline" size="sm" @click="unmute(item.unmute_url)">{{ t('forum.muted.unmute') }}</Button>
      </div>
    </div>
  </section>

  <p v-if="!topicMutes.length && !sectionMutes.length" class="text-sm text-muted-foreground">{{ t('forum.muted.empty') }}</p>
</template>
