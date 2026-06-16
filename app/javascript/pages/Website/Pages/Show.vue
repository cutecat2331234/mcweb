<script setup lang="ts">
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'

defineOptions({ layout: WebsiteLayout })

defineProps<{
  page: { title: string; slug?: string }
  blocks: Array<{
    block_type: string
    settings: Record<string, string>
  }>
}>()
</script>

<template>
  <section class="website-page-hero mx-auto max-w-4xl">
    <h1 class="website-hero-title">{{ page.title }}</h1>
  </section>

  <section class="mx-auto max-w-4xl space-y-8 px-4 pb-20">
    <article
      v-for="(block, index) in blocks"
      :key="index"
      class="website-card !p-0 overflow-hidden"
    >
      <template v-if="block.block_type === 'hero'">
        <div class="website-block-hero">
          <h2>{{ block.settings.headline }}</h2>
          <p v-if="block.settings.subheadline" class="mx-auto mt-3 max-w-2xl text-lg text-slate-300">
            {{ block.settings.subheadline }}
          </p>
          <a
            v-if="block.settings.cta_text && block.settings.cta_url"
            :href="block.settings.cta_url"
            class="website-btn website-btn-primary mt-8 inline-flex"
          >
            {{ block.settings.cta_text }}
          </a>
        </div>
      </template>
      <div
        v-else-if="block.block_type === 'rich_text'"
        class="website-prose p-6 md:p-8"
        v-html="block.settings.html"
      />
      <div v-else class="p-6 text-sm text-slate-400">[{{ block.block_type }}]</div>
    </article>
  </section>
</template>
