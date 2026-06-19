<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const props = defineProps<{
  emoji: string
  count: number
  users: string[]
}>()

const open = ref(false)

function toggle() {
  if (!props.users.length) return
  open.value = !open.value
}
</script>

<template>
  <span class="relative inline-block">
    <button
      type="button"
      class="rounded-full border px-2 py-0.5 text-xs transition-colors hover:bg-muted"
      :class="open ? 'border-primary bg-primary/10' : ''"
      @click="toggle"
    >
      {{ emoji }}
      <span v-if="count">{{ count }}</span>
    </button>
    <div
      v-if="open && users.length"
      class="absolute bottom-full left-0 z-10 mb-1 min-w-[10rem] rounded-md border bg-popover p-2 text-xs shadow-md"
    >
      <p class="mb-1 font-medium text-muted-foreground">{{ t('components.reactionUsers.title') }}</p>
      <ul class="space-y-0.5">
        <li v-for="username in users" :key="username">{{ username }}</li>
      </ul>
    </div>
  </span>
</template>
