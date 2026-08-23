<script setup lang="ts">
import { computed, onErrorCaptured, ref } from 'vue'
import { Alert, Button, Space, TypographyText } from '@mcweb/ui'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  applicationId: string
}>()

const failure = ref<Error | null>(null)
const { locale } = useI18n()
const copy = computed(() => locale.value.toLowerCase().startsWith('zh')
  ? {
      title: '应用暂时不可用',
      detail: '此应用遇到问题，无法继续显示当前页面。',
      reload: '重新载入应用',
    }
  : {
      title: 'Application unavailable',
      detail: 'This application encountered a problem and cannot display the current page.',
      reload: 'Reload application',
    })

onErrorCaptured((error) => {
  failure.value = error instanceof Error ? error : new Error(String(error))
  console.error(`[McWeb] ${props.applicationId} rendering failed`, error)
  return false
})

function reload() {
  window.location.reload()
}
</script>

<template>
  <slot v-if="!failure" />
  <main v-else class="mc-application-error" role="main">
    <Alert type="error" :title="copy.title">
      <Space direction="vertical" fill :size="12">
        <TypographyText role="alert" aria-live="assertive">
          {{ copy.detail }}
        </TypographyText>
        <Button type="primary" @click="reload">{{ copy.reload }}</Button>
      </Space>
    </Alert>
  </main>
</template>
