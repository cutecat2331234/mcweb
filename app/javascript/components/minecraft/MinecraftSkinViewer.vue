<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = withDefaults(defineProps<{
  username: string
  skinTextureUrl?: string | null
  skinModel?: string | null
  width?: number
  height?: number
}>(), {
  width: 200,
  height: 280,
})

const canvasRef = ref<HTMLCanvasElement | null>(null)
let viewer: { dispose: () => void; loadSkin: (url: string, options?: { model?: string }) => Promise<void> } | null = null
let mountGeneration = 0

function resolveSkinUrl(): string | null {
  if (typeof props.skinTextureUrl !== 'string') return null
  return /^\/minecraft\/cached-skins\/\d+\/skin$/.test(props.skinTextureUrl)
    ? props.skinTextureUrl
    : null
}

async function mountViewer() {
  const generation = ++mountGeneration
  const canvas = canvasRef.value
  const skinUrl = resolveSkinUrl()
  viewer?.dispose()
  viewer = null
  if (!canvas || !skinUrl) return

  try {
    const { SkinViewer } = await import('skinview3d')
    if (generation !== mountGeneration || canvasRef.value !== canvas) return

    const nextViewer = new SkinViewer({
      canvas,
      width: props.width,
      height: props.height,
    })
    viewer = nextViewer
    await nextViewer.loadSkin(skinUrl, {
      model: props.skinModel === 'slim' ? 'slim' : 'default',
    })
  } catch {
    if (generation === mountGeneration) {
      viewer?.dispose()
      viewer = null
    }
  }
}

onMounted(() => {
  void mountViewer()
})

watch(
  () => [props.skinTextureUrl, props.username, props.skinModel, props.width, props.height],
  () => {
    void mountViewer()
  },
)

onBeforeUnmount(() => {
  mountGeneration += 1
  viewer?.dispose()
  viewer = null
})
</script>

<template>
  <canvas
    ref="canvasRef"
    :width="width"
    :height="height"
    class="rounded-lg border bg-muted"
    :aria-label="username"
  />
</template>
