<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { usePage } from '@inertiajs/vue3'

interface FlashMessage {
  index: number
  type: 'success' | 'error'
  text: string
}

const page = usePage()
const dismissed = ref<Set<number>>(new Set())
const autoHidden = ref(false)

const messages = computed<FlashMessage[]>(() => {
  const flash = page.props.flash as { notice?: string; alert?: string } | undefined
  const items: FlashMessage[] = []
  if (flash?.notice) items.push({ index: 0, type: 'success', text: flash.notice })
  if (flash?.alert) items.push({ index: 1, type: 'error', text: flash.alert })
  return items
})

const visibleMessages = computed(() => {
  if (autoHidden.value) return []
  return messages.value.filter((message) => !dismissed.value.has(message.index))
})

function dismiss(index: number) {
  dismissed.value = new Set([...dismissed.value, index])
}

watch(
  messages,
  (current) => {
    dismissed.value = new Set()
    autoHidden.value = false
    if (!current.length) return
    window.setTimeout(() => {
      autoHidden.value = true
    }, 6000)
  },
  { immediate: true },
)
</script>

<template>
  <a-space v-if="visibleMessages.length" direction="vertical" fill class="mb-4">
    <a-alert
      v-for="message in visibleMessages"
      :key="message.index"
      :type="message.type"
      show-icon
      closable
      role="alert"
      @close="dismiss(message.index)"
    >
      {{ message.text }}
    </a-alert>
  </a-space>
</template>
