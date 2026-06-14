<script setup lang="ts">
import { computed, watch } from 'vue'
import { usePage } from '@inertiajs/vue3'

const page = usePage()

const flash = computed(() => page.props.flash as { notice?: string; alert?: string } | undefined)

const messages = computed(() => {
  const items: Array<{ type: 'notice' | 'alert'; text: string }> = []
  if (flash.value?.notice) items.push({ type: 'notice', text: flash.value.notice })
  if (flash.value?.alert) items.push({ type: 'alert', text: flash.value.alert })
  return items
})

watch(messages, (current) => {
  if (!current.length) return
  window.setTimeout(() => {
    if (flash.value) {
      flash.value.notice = undefined
      flash.value.alert = undefined
    }
  }, 5000)
})
</script>

<template>
  <div v-if="messages.length" class="mb-4 space-y-2">
    <div
      v-for="(message, index) in messages"
      :key="index"
      class="rounded-md border px-4 py-3 text-sm"
      :class="message.type === 'notice'
        ? 'border-emerald-200 bg-emerald-50 text-emerald-900 dark:border-emerald-900 dark:bg-emerald-950 dark:text-emerald-100'
        : 'border-red-200 bg-red-50 text-red-900 dark:border-red-900 dark:bg-red-950 dark:text-red-100'"
      role="alert"
    >
      {{ message.text }}
    </div>
  </div>
</template>
