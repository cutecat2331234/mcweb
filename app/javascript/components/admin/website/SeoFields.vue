<script setup lang="ts">
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

const seo = defineModel<Record<string, string>>('seo', { required: true })

defineProps<{ prefix?: string }>()
</script>

<template>
  <div class="space-y-4">
    <div class="space-y-2">
      <Label>Meta title</Label>
      <Input v-model="seo.title" />
    </div>
    <div class="space-y-2">
      <Label>Meta description</Label>
      <Input v-model="seo.description" />
    </div>
    <div class="space-y-2">
      <Label>OG image URL</Label>
      <Input v-model="seo.og_image" type="url" />
    </div>
  </div>
</template>
