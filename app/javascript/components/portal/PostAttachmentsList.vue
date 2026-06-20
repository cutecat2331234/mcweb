<script setup lang="ts">
import { useI18n } from 'vue-i18n'

defineProps<{
  attachments: Array<{
    id: number
    filename: string
    human_size: string
    download_url: string
    download_count?: number
  }>
}>()

const { t } = useI18n()
</script>

<template>
  <ul v-if="attachments.length" class="mt-3 space-y-1 rounded-md border bg-muted/30 p-3 text-sm">
    <li class="text-xs font-medium text-muted-foreground">{{ t('forum.topics.attachments') }}</li>
    <li v-for="attachment in attachments" :key="attachment.id">
      <a :href="attachment.download_url" class="inline-flex items-center gap-2 text-primary hover:underline">
        <span>{{ attachment.filename }}</span>
        <span class="text-xs text-muted-foreground">({{ attachment.human_size }})</span>
        <span v-if="attachment.download_count" class="text-xs text-muted-foreground">
          · {{ t('forum.topics.downloadCount', { n: attachment.download_count }) }}
        </span>
      </a>
    </li>
  </ul>
</template>
