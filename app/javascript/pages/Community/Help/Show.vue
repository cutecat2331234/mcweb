<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  article: { title: string; category: string; body_html: string }
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.help.breadcrumb'), href: routes.forumHelp },
    { label: article.title, current: true },
  ]" />

  <PageHeader :title="article.title" />

  <article class="prose prose-sm max-w-3xl dark:prose-invert" v-html="article.body_html" />
</template>
