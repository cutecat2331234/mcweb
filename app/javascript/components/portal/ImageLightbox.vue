<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'

const open = ref(false)
const src = ref('')
const alt = ref('')

function openImage(url: string, description = '') {
  src.value = url
  alt.value = description
  open.value = true
}

function close() {
  open.value = false
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'Escape') close()
}

function onDocumentClick(event: MouseEvent) {
  const target = event.target as HTMLElement | null
  const image = target?.closest('img.post-image') as HTMLImageElement | null
  if (!image) return
  event.preventDefault()
  openImage(image.src, image.alt || '')
}

onMounted(() => {
  document.addEventListener('click', onDocumentClick)
  document.addEventListener('keydown', onKeydown)
})

onUnmounted(() => {
  document.removeEventListener('click', onDocumentClick)
  document.removeEventListener('keydown', onKeydown)
})
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-black/80 p-4"
      role="dialog"
      aria-modal="true"
      @click="close"
    >
      <img :src="src" :alt="alt" class="max-h-[90vh] max-w-full rounded shadow-lg" @click.stop />
      <button
        type="button"
        class="absolute right-4 top-4 rounded bg-black/50 px-3 py-1 text-sm text-white"
        @click="close"
      >
        关闭
      </button>
    </div>
  </Teleport>
</template>
