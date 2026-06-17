<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { AlertCircle, CheckCircle2, X } from '@lucide/vue'
import { cn } from '@/lib/utils'

const page = usePage()
const dismissed = ref<Set<number>>(new Set())

const flash = computed(() => page.props.flash as { notice?: string; alert?: string } | undefined)

const messages = computed(() => {
  const items: Array<{ type: 'notice' | 'alert'; text: string }> = []
  if (flash.value?.notice) items.push({ type: 'notice', text: flash.value.notice })
  if (flash.value?.alert) items.push({ type: 'alert', text: flash.value.alert })
  return items
})

const visibleMessages = computed(() =>
  messages.value.filter((_, index) => !dismissed.value.has(index)),
)

function dismiss(index: number) {
  dismissed.value = new Set([ ...dismissed.value, index ])
}

watch(messages, (current) => {
  dismissed.value = new Set()
  if (!current.length) return
  window.setTimeout(() => {
    if (flash.value) {
      flash.value.notice = undefined
      flash.value.alert = undefined
    }
  }, 6000)
})
</script>

<template>
  <div v-if="visibleMessages.length" class="mb-6 space-y-3">
    <div
      v-for="(message, index) in messages"
      v-show="!dismissed.has(index)"
      :key="index"
      role="alert"
      :class="cn(
        'relative flex gap-3 rounded-lg border px-4 py-3 pr-10 text-sm shadow-sm',
        message.type === 'notice'
          ? 'border-emerald-200/80 bg-emerald-50 text-emerald-900 dark:border-emerald-800 dark:bg-emerald-950/50 dark:text-emerald-100'
          : 'border-red-200/80 bg-red-50 text-red-900 dark:border-red-800 dark:bg-red-950/50 dark:text-red-100',
      )"
    >
      <CheckCircle2
        v-if="message.type === 'notice'"
        class="mt-0.5 h-4 w-4 shrink-0 text-emerald-600 dark:text-emerald-400"
      />
      <AlertCircle
        v-else
        class="mt-0.5 h-4 w-4 shrink-0 text-red-600 dark:text-red-400"
      />
      <p class="min-w-0 flex-1 leading-relaxed">{{ message.text }}</p>
      <button
        type="button"
        class="absolute right-2 top-2 rounded-md p-1 opacity-70 transition-opacity hover:opacity-100"
        aria-label="关闭"
        @click="dismiss(index)"
      >
        <X class="h-4 w-4" />
      </button>
    </div>
  </div>
</template>
