<script setup lang="ts">
const props = defineProps<{
  locales: string[]
  fields: Array<'title' | 'summary' | 'description'>
}>()

const translations = defineModel<Record<string, Record<string, unknown>>>('translations', {
  required: true,
})

function ensure(locale: string) {
  if (!translations.value[locale]) translations.value[locale] = {}
  return translations.value[locale] as Record<string, string>
}

function ensureSeo(locale: string) {
  const data = ensure(locale)
  if (!data.seo || typeof data.seo !== 'object') {
    data.seo = {} as unknown as string
  }
  return data.seo as unknown as Record<string, string>
}
</script>

<template>
  <a-space direction="vertical" fill>
    <a-card v-for="locale in props.locales" :key="locale" :title="locale" :bordered="true">
      <a-form :model="ensure(locale)" layout="vertical">
        <a-form-item v-if="fields.includes('title')" field="title" label="Title">
          <a-input v-model="ensure(locale).title" allow-clear />
        </a-form-item>
        <a-form-item v-if="fields.includes('summary')" field="summary" label="Summary">
          <a-textarea
            v-model="ensure(locale).summary"
            :auto-size="{ minRows: 2, maxRows: 6 }"
          />
        </a-form-item>
        <a-form-item field="seo.title" label="SEO title">
          <a-input v-model="ensureSeo(locale).title" allow-clear />
        </a-form-item>
        <a-form-item
          v-if="fields.includes('description')"
          field="seo.description"
          label="SEO description"
        >
          <a-textarea
            v-model="ensureSeo(locale).description"
            :auto-size="{ minRows: 2, maxRows: 6 }"
          />
        </a-form-item>
      </a-form>
    </a-card>
  </a-space>
</template>
