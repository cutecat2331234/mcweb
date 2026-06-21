<script setup lang="ts">
import { Head } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'

defineOptions({ layout: WebsiteLayout })

const { t } = useI18n()

defineProps<{
  page: { title: string; slug?: string }
  blocks: Array<{ block_type: string; settings: Record<string, string> }>
  seo?: { title?: string; description?: string; og_image?: string }
}>()
</script>

<template>
  <Head>
    <title>{{ seo?.title || page.title }}</title>
    <meta v-if="seo?.description" head-key="description" name="description" :content="seo.description" />
    <meta v-if="seo?.og_image" head-key="og:image" property="og:image" :content="seo.og_image" />
  </Head>

  <section class="website-page-hero mx-auto max-w-4xl">
    <h1 class="website-hero-title">{{ page.title }}</h1>
  </section>

  <section class="mx-auto max-w-4xl space-y-8 px-4 pb-20">
    <article v-for="(block, index) in blocks" :key="index" class="website-card !p-0 overflow-hidden">
      <template v-if="block.block_type === 'hero'">
        <div class="website-block-hero">
          <h2>{{ block.settings.headline }}</h2>
          <p v-if="block.settings.subheadline" class="mx-auto mt-3 max-w-2xl text-lg text-slate-300">{{ block.settings.subheadline }}</p>
          <a v-if="block.settings.cta_text && block.settings.cta_url" :href="block.settings.cta_url" rel="noopener noreferrer" class="website-btn website-btn-primary mt-8 inline-flex">{{ block.settings.cta_text }}</a>
        </div>
      </template>
      <div v-else-if="block.block_type === 'rich_text'" class="website-prose p-6 md:p-8" v-html="block.settings.html" />
      <div v-else class="p-6 text-sm text-slate-400">{{ t('website.pages.unknownBlock', { type: block.block_type }) }}</div>
    </article>
  </section>
</template>
