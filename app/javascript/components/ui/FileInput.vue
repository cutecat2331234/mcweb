<script setup lang="ts">
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
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
    buttonVariant: 'outline',
    buttonSize: 'sm',
  },
)

const { t } = useI18n()
const displayLabel = computed(() => props.buttonLabel || t('components.fileInput.chooseFile'))

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
      <slot>{{ displayLabel }}</slot>
    </Button>
  </div>
</template>
