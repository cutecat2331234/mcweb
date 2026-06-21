<script setup lang="ts">
import { Head, Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: WebsiteLayout })

const { t } = useI18n()

defineProps<{
  article: {
    title: string
    summary: string | null
    published_at: string | null
    body_html?: string
    slug?: string
  }
  seo?: { title?: string; description?: string; og_image?: string }
}>()
</script>

<template>
  <Head>
    <title>{{ seo?.title || article.title }}</title>
    <meta v-if="seo?.description" head-key="description" name="description" :content="seo.description" />
    <meta v-if="seo?.og_image" head-key="og:image" property="og:image" :content="seo.og_image" />
  </Head>

  <section class="mx-auto max-w-3xl px-4 py-16">
    <PageHeader :title="article.title" :subtitle="article.published_at || undefined" />
    <div v-if="article.summary" class="prose prose-invert mb-8 max-w-none text-slate-300">{{ article.summary }}</div>
    <div v-if="article.body_html" class="website-prose prose prose-invert max-w-none" v-html="article.body_html" />
    <Link :href="routes.blog" class="mt-8 inline-block text-sky-300 hover:underline">{{ t('website.articles.backToBlog') }}</Link>
  </section>
</template>
