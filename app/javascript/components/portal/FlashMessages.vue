<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { Alert, Space } from '@mcweb/ui'

const page = usePage()
const dismissed = ref<Set<number>>(new Set())
const autoHidden = ref(false)

const flash = computed(() => page.props.flash as { notice?: string; alert?: string } | undefined)

const messages = computed(() => {
  const items: Array<{ type: 'notice' | 'alert'; text: string }> = []
  if (flash.value?.notice) items.push({ type: 'notice', text: flash.value.notice })
  if (flash.value?.alert) items.push({ type: 'alert', text: flash.value.alert })
  return items
})

const visibleMessages = computed(() => {
  if (autoHidden.value) return []
  return messages.value
    .map((message, index) => ({ ...message, index }))
    .filter(({ index }) => !dismissed.value.has(index))
})

function dismiss(index: number) {
  dismissed.value = new Set([ ...dismissed.value, index ])
}

watch(messages, (current) => {
  dismissed.value = new Set()
  autoHidden.value = false
  if (!current.length) return
  window.setTimeout(() => {
    autoHidden.value = true
  }, 6000)
})
</script>

<template>
  <Space
    v-if="visibleMessages.length"
    direction="vertical"
    fill
    size="medium"
    data-portal-flash-messages
  >
    <Alert
      v-for="message in visibleMessages"
      :key="message.index"
      role="alert"
      :type="message.type === 'notice' ? 'success' : 'error'"
      show-icon
      closable
      @close="dismiss(message.index)"
    >
      {{ message.text }}
    </Alert>
  </Space>
</template>
