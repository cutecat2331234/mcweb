<script setup lang="ts">
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'

defineOptions({ layout: WebsiteLayout })

defineProps<{
  page: { title: string }
  blocks: Array<{
    block_type: string
    settings: Record<string, string>
  }>
}>()
</script>

<template>
  <section class="mx-auto max-w-4xl px-4 py-16">
    <PageHeader :title="page.title" />

    <article v-for="(block, index) in blocks" :key="index" class="mb-8 border-b border-white/10 pb-8">
      <template v-if="block.block_type === 'hero'">
        <h2 class="text-2xl font-bold text-white">{{ block.settings.headline }}</h2>
        <p class="mt-2 text-slate-300">{{ block.settings.subheadline }}</p>
      </template>
      <div v-else-if="block.block_type === 'rich_text'" class="prose prose-invert max-w-none" v-html="block.settings.html" />
      <p v-else class="text-sm text-slate-400">[{{ block.block_type }}]</p>
    </article>
  </section>
</template>
