<script setup lang="ts">
import { Alert, Button, Space, Tag, TypographyText } from '@mcweb/ui'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  document_url: string
  return_url: string
  edit_url: string
  label: string
  mode_label: string
}>()

const { t } = useI18n()

function leavePreview(path: string) {
  window.location.assign(path)
}
</script>

<template>
  <main class="mc-website-preview-frame">
    <div class="mc-website-preview-frame__toolbar">
      <Space align="center" :size="10">
        <Tag color="purple">{{ mode_label }}</Tag>
        <TypographyText bold>{{ label }}</TypographyText>
      </Space>
      <Space align="center" :size="8">
        <Button @click="leavePreview(edit_url)">{{ t('common.edit') }}</Button>
        <Button type="primary" @click="leavePreview(return_url)">{{ t('common.back') }}</Button>
      </Space>
    </div>
    <Alert v-if="!document_url" type="error" :title="t('common.error')" />
    <iframe
      v-else
      class="mc-website-preview-frame__canvas"
      :src="document_url"
      :title="label"
      referrerpolicy="same-origin"
    />
  </main>
</template>
