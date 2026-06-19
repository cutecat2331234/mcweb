<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import MinecraftSkinViewer from '@/components/minecraft/MinecraftSkinViewer.vue'

export interface MinecraftField {
  key: string
  label: string
  value: string
  field_type: string
  group?: string | null
}

export interface MinecraftProfile {
  linked: boolean
  player_id?: string
  username?: string
  uuid?: string
  identity_type?: string
  skin_texture_url?: string | null
  skin_model?: string | null
  last_seen_ingame_at?: string | null
  fields?: MinecraftField[]
  link_url?: string | null
}

const props = defineProps<{
  minecraft: MinecraftProfile
  skinMode?: string
}>()

const { t } = useI18n()

const show2d = computed(() => !props.skinMode || props.skinMode === '2d' || props.skinMode === 'both')
const show3d = computed(() => props.skinMode === '3d' || props.skinMode === 'both')

const skinUrl = computed(() => {
  if (!props.minecraft.linked || !props.minecraft.username) return null
  if (props.minecraft.uuid) {
    return `https://crafatar.com/avatars/${encodeURIComponent(props.minecraft.uuid)}?size=128&overlay`
  }
  if (props.minecraft.skin_texture_url && /^https?:\/\//i.test(props.minecraft.skin_texture_url)) {
    return props.minecraft.skin_texture_url
  }
  return `https://mineskin.eu/avatar/${encodeURIComponent(props.minecraft.username)}/128.png`
})

const bodySkinUrl = computed(() => {
  if (!props.minecraft.linked || !props.minecraft.username) return null
  if (props.minecraft.uuid) {
    return `https://crafatar.com/renders/body/${encodeURIComponent(props.minecraft.uuid)}?overlay`
  }
  return `https://mineskin.eu/armor/body/${encodeURIComponent(props.minecraft.username)}`
})
</script>

<template>
  <section v-if="minecraft.linked" class="rounded-xl border bg-card p-4">
    <h3 class="mb-3 text-sm font-semibold">{{ t('minecraft.title') }}</h3>
    <div class="flex flex-col gap-4 sm:flex-row sm:items-start">
      <div class="flex shrink-0 flex-col items-center gap-2">
        <img
          v-if="show2d && skinUrl"
          :src="skinUrl"
          :alt="minecraft.username"
          class="h-24 w-24 rounded-lg border bg-muted object-cover"
        >
        <img
          v-if="show2d && show3d && bodySkinUrl"
          :src="bodySkinUrl"
          :alt="`${minecraft.username} ${t('minecraft.link.fullBody')}`"
          class="h-32 rounded-lg border bg-muted object-contain"
        >
        <MinecraftSkinViewer
          v-if="show3d && minecraft.username"
          :username="minecraft.username"
          :uuid="minecraft.uuid"
          :skin-texture-url="minecraft.skin_texture_url"
          :skin-model="minecraft.skin_model"
        />
      </div>
      <div class="min-w-0 flex-1 space-y-2 text-sm">
        <div class="flex flex-wrap items-center gap-2">
          <span class="font-medium">{{ minecraft.username }}</span>
          <Badge variant="outline">{{ minecraft.identity_type }}</Badge>
        </div>
        <p v-if="minecraft.player_id" class="text-xs text-muted-foreground">
          {{ t('minecraft.link.playerId', { id: minecraft.player_id }) }}
        </p>
        <p v-if="minecraft.last_seen_ingame_at" class="text-xs text-muted-foreground">
          {{ t('minecraft.link.lastSeenAt', { time: minecraft.last_seen_ingame_at }) }}
        </p>
        <dl v-if="minecraft.fields?.length" class="grid gap-2 sm:grid-cols-2">
          <div v-for="field in minecraft.fields" :key="field.key">
            <dt class="text-xs text-muted-foreground">{{ field.label }}</dt>
            <dd class="font-medium break-words">{{ field.value }}</dd>
          </div>
        </dl>
      </div>
    </div>
  </section>

  <section v-else-if="minecraft.link_url" class="rounded-xl border border-dashed bg-muted/30 p-4 text-sm">
    <p class="mb-2 text-muted-foreground">{{ t('minecraft.link.notLinked') }}</p>
    <Button as-child size="sm">
      <Link :href="minecraft.link_url">{{ t('minecraft.link.goLink') }}</Link>
    </Button>
  </section>
</template>
