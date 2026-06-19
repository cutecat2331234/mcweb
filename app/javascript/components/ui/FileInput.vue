<script setup lang="ts">
import { ref } from 'vue'
import Button from '@/components/ui/Button.vue'

const props = withDefaults(
  defineProps<{
    accept?: string
    disabled?: boolean
    multiple?: boolean
    buttonLabel?: string
    buttonVariant?: 'default' | 'outline' | 'secondary' | 'destructive' | 'ghost'
    buttonSize?: 'default' | 'sm' | 'lg' | 'icon'
  }>(),
  {
    accept: '*/*',
    disabled: false,
    multiple: false,
    buttonLabel: '选择文件',
    buttonVariant: 'outline',
    buttonSize: 'sm',
  },
)

const emit = defineEmits<{ change: [files: File | File[]] }>()

const inputRef = ref<HTMLInputElement | null>(null)

function openPicker() {
  if (props.disabled) return
  inputRef.value?.click()
}

function onChange(event: Event) {
  const fileList = (event.target as HTMLInputElement).files
  if (!fileList?.length) return
  emit('change', props.multiple ? Array.from(fileList) : fileList[0])
  if (inputRef.value) inputRef.value.value = ''
}
</script>

<template>
  <div class="inline-flex">
    <input
      ref="inputRef"
      type="file"
      class="sr-only"
      :accept="accept"
      :disabled="disabled"
      :multiple="multiple"
      @change="onChange"
    >
    <Button
      type="button"
      :variant="buttonVariant"
      :size="buttonSize"
      :disabled="disabled"
      @click="openPicker"
    >
      <slot>{{ buttonLabel }}</slot>
    </Button>
  </div>
</template>
