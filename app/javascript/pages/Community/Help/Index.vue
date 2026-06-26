<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  categories: Array<{ category: string; articles: Array<{ title: string; slug: string; url: string }> }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.help.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.help.title')" :subtitle="t('forum.help.subtitle')" />

  <div v-if="categories.length" class="space-y-6">
    <section v-for="group in categories" :key="group.category" class="rounded-lg border p-4">
      <h2 class="mb-3 text-sm font-semibold capitalize">{{ group.category }}</h2>
      <ul class="space-y-1">
        <li v-for="article in group.articles" :key="article.slug">
          <Link :href="article.url" class="text-sm text-primary hover:underline">{{ article.title }}</Link>
        </li>
      </ul>
    </section>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('forum.help.empty') }}</p>
</template>
