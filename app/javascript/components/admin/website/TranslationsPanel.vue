<script setup lang="ts">
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

const props = defineProps<{
  locales: string[]
  fields: Array<'title' | 'summary' | 'description'>
}>()

const translations = defineModel<Record<string, Record<string, unknown>>>('translations', { required: true })

function ensure(locale: string) {
  if (!translations.value[locale]) translations.value[locale] = {}
  return translations.value[locale] as Record<string, string>
}

function ensureSeo(locale: string) {
  const data = ensure(locale)
  if (!data.seo || typeof data.seo !== 'object') data.seo = {} as unknown as string
  return data.seo as unknown as Record<string, string>
}
</script>

<template>
  <div class="space-y-6">
    <div v-for="locale in locales" :key="locale" class="rounded-lg border p-4 space-y-3">
      <h3 class="text-sm font-semibold">{{ locale }}</h3>
      <div v-if="fields.includes('title')" class="space-y-2">
        <Label>Title</Label>
        <Input v-model="ensure(locale).title" />
      </div>
      <div v-if="fields.includes('summary')" class="space-y-2">
        <Label>Summary</Label>
        <Input v-model="ensure(locale).summary" />
      </div>
      <div class="space-y-2">
        <Label>SEO title</Label>
        <Input v-model="ensureSeo(locale).title" />
      </div>
      <div v-if="fields.includes('description')" class="space-y-2">
        <Label>SEO description</Label>
        <Input v-model="ensureSeo(locale).description" />
      </div>
    </div>
  </div>
</template>
