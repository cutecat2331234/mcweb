<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'

const progress = ref(0)
const progressElement = ref<HTMLElement | null>(null)
let scrollRegion: HTMLElement | null = null
let resizeObserver: ResizeObserver | null = null

function updateProgress() {
  const viewport = scrollRegion?.clientHeight ?? window.innerHeight
  const contentHeight = scrollRegion?.scrollHeight ?? document.documentElement.scrollHeight
  const scrollTop = scrollRegion?.scrollTop ?? window.scrollY
  const distance = contentHeight - viewport
  progress.value = distance > 0 ? Math.max(0, Math.min(100, (scrollTop / distance) * 100)) : 0
}

onMounted(() => {
  scrollRegion = progressElement.value?.closest<HTMLElement>('[scroll-region]') ?? null
  ;(scrollRegion ?? window).addEventListener('scroll', updateProgress, { passive: true })
  window.addEventListener('resize', updateProgress)
  resizeObserver = new ResizeObserver(updateProgress)
  resizeObserver.observe(scrollRegion?.firstElementChild ?? document.body)
  updateProgress()
})

onUnmounted(() => {
  ;(scrollRegion ?? window).removeEventListener('scroll', updateProgress)
  window.removeEventListener('resize', updateProgress)
  resizeObserver?.disconnect()
})
</script>

<template>
  <div
    ref="progressElement"
    class="pointer-events-none fixed left-0 top-0 z-50 h-0.5 bg-primary transition-[width] duration-75"
    :style="{ width: `${progress}%` }"
    aria-hidden="true"
  />
</template>
