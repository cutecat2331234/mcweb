<script setup lang="ts">
import { onErrorCaptured, ref } from 'vue'
import { Alert, Button, Space, TypographyText } from '@mcweb/ui'
import { useI18n } from 'vue-i18n'

const props = defineProps<{
  applicationId: string
}>()

const failure = ref<Error | null>(null)
const { t } = useI18n()

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
    <Alert type="error" :title="t('common.applicationUnavailable')">
      <Space direction="vertical" fill :size="12">
        <TypographyText role="alert" aria-live="assertive">
          {{ t('common.applicationUnavailableDetail') }}
        </TypographyText>
        <Button type="primary" @click="reload">{{ t('common.reloadApplication') }}</Button>
      </Space>
    </Alert>
  </main>
</template>
