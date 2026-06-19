<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = withDefaults(defineProps<{
  username: string
  uuid?: string | null
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

function isHttpUrl(value: string | null | undefined): value is string {
  return typeof value === 'string' && /^https?:\/\//i.test(value)
}

function resolveSkinUrl(): string | null {
  if (isHttpUrl(props.skinTextureUrl)) return props.skinTextureUrl
  if (props.uuid) return `https://crafatar.com/skins/${encodeURIComponent(props.uuid)}`
  if (props.username) return `https://mineskin.eu/skin/${encodeURIComponent(props.username)}`
  return null
}

async function mountViewer() {
  const canvas = canvasRef.value
  const skinUrl = resolveSkinUrl()
  if (!canvas || !skinUrl) return

  const { SkinViewer } = await import('skinview3d')
  viewer?.dispose()
  viewer = new SkinViewer({
    canvas,
    width: props.width,
    height: props.height,
    skin: skinUrl,
    model: props.skinModel === 'slim' ? 'slim' : 'default',
  })
}

onMounted(() => {
  void mountViewer()
})

watch(
  () => [props.skinTextureUrl, props.uuid, props.username, props.skinModel, props.width, props.height],
  () => {
    void mountViewer()
  },
)

onBeforeUnmount(() => {
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
