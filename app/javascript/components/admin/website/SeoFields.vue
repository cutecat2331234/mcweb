<script setup lang="ts">
import { useI18n } from 'vue-i18n'

const { t } = useI18n()
const seo = defineModel<Record<string, string>>('seo', { required: true })
</script>

<template>
  <a-form :model="seo" layout="vertical">
    <a-form-item field="title" :label="t('admin.website.seoFields.metaTitle')">
      <a-input v-model="seo.title" allow-clear />
    </a-form-item>
    <a-form-item field="description" :label="t('admin.website.seoFields.metaDescription')">
      <a-textarea v-model="seo.description" :auto-size="{ minRows: 3, maxRows: 8 }" />
    </a-form-item>
    <a-form-item field="og_image" :label="t('admin.website.seoFields.openGraphImageUrl')">
      <a-input v-model="seo.og_image" type="url" allow-clear />
    </a-form-item>
  </a-form>
</template>
