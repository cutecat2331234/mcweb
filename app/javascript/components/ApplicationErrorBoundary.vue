<script setup lang="ts">
import { onErrorCaptured, ref } from 'vue'
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
    <section class="mc-application-error__message" role="alert" aria-live="assertive">
      <h1>{{ t('common.applicationUnavailable') }}</h1>
      <p>{{ t('common.applicationUnavailableDetail') }}</p>
      <button type="button" @click="reload">{{ t('common.reloadApplication') }}</button>
    </section>
  </main>
</template>

<style scoped>
/* The failure surface must work without loading the UI kit it may be guarding. */
.mc-application-error {
  padding: 24px;
  color: var(--color-text-1, #1d2129);
}

.mc-application-error__message {
  max-width: 640px;
  margin-inline: auto;
  padding: 20px;
  border: 1px solid rgb(var(--danger-3, 251, 172, 163));
  border-radius: 8px;
  background: var(--color-bg-2, #fff);
}

h1 {
  margin: 0;
  font-size: 18px;
}

p {
  margin-block: 12px;
  line-height: 1.6;
}

button {
  padding: 8px 16px;
  border: 0;
  border-radius: 4px;
  background: rgb(var(--primary-6, 22, 93, 255));
  color: #fff;
  font: inherit;
  cursor: pointer;
}

button:focus-visible {
  outline: 2px solid rgb(var(--primary-6, 22, 93, 255));
  outline-offset: 3px;
}
</style>
