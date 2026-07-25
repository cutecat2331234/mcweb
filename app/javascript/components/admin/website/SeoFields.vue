<script setup lang="ts">
const seo = defineModel<Record<string, string>>('seo', { required: true })
</script>

<template>
  <a-form :model="seo" layout="vertical">
    <a-form-item field="title" label="Meta title">
      <a-input v-model="seo.title" allow-clear />
    </a-form-item>
    <a-form-item field="description" label="Meta description">
      <a-textarea v-model="seo.description" :auto-size="{ minRows: 3, maxRows: 8 }" />
    </a-form-item>
    <a-form-item field="og_image" label="Open Graph image URL">
      <a-input v-model="seo.og_image" type="url" allow-clear />
    </a-form-item>
  </a-form>
</template>
