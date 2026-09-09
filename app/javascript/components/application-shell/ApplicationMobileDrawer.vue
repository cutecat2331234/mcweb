<script setup lang="ts">
import { nextTick, onMounted } from 'vue'
import { Drawer } from '@mcweb/ui'

withDefaults(defineProps<{
  ariaLabel: string
  width?: string | number
  placement?: 'left' | 'right' | 'top' | 'bottom'
  header?: boolean
}>(), {
  width: 'min(var(--mc-shell-drawer-width, 280px), 100vw)',
  placement: 'left',
  header: false,
})

const visible = defineModel<boolean>('visible', { required: true })
const emit = defineEmits<{ ready: [] }>()

onMounted(async () => {
  await nextTick()
  emit('ready')
})
</script>

<template>
  <Drawer
    v-model:visible="visible"
    :placement="placement"
    :width="width"
    :footer="false"
    :header="header"
    :aria-label="ariaLabel"
    aria-modal="true"
    role="dialog"
    unmount-on-close
  >
    <slot />
  </Drawer>
</template>
