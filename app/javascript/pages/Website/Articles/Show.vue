<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: WebsiteLayout })

defineProps<{
  article: {
    title: string
    summary: string | null
    published_at: string | null
  }
}>()
</script>

<template>
  <section class="mx-auto max-w-3xl px-4 py-16">
    <PageHeader :title="article.title" :subtitle="article.published_at || undefined" />
    <div v-if="article.summary" class="prose prose-invert max-w-none whitespace-pre-wrap text-slate-200">
      {{ article.summary }}
    </div>
    <Link :href="routes.blog" class="mt-8 inline-block text-sky-300 hover:underline">返回博客</Link>
  </section>
</template>
