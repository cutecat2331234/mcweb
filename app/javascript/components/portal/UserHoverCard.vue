<script setup lang="ts">
import { onBeforeUnmount, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const props = defineProps<{
  username: string
  cardUrl: string
}>()

export interface UserCardData {
  username: string
  display_name: string | null
  avatar_url: string
  profile_url: string
  trust_level: number
  trust_name: string
  posts_count: number
  likes_received?: number
  bio?: string | null
  member_since: string
  last_seen_at?: string | null
  online?: boolean
  badges: Array<{ name: string; icon: string | null; color: string | null; granted_at?: string }>
  memberships?: Array<{ name: string; slug: string; color?: string | null; icon?: string | null; expires_label?: string; permanent?: boolean }>
  message_url: string | null
  follow_url?: string | null
  following?: boolean
  ingame_online?: boolean
  ingame_server?: string | null
  last_seen_ingame_at?: string | null
}

const open = ref(false)
const loading = ref(false)
const card = ref<UserCardData | null>(null)
let hoverTimer: ReturnType<typeof setTimeout> | null = null

async function loadCard() {
  if (card.value || loading.value) return
  loading.value = true
  try {
    const response = await fetch(props.cardUrl, {
      headers: { Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (response.ok) {
      card.value = await response.json()
    }
  } finally {
    loading.value = false
  }
}

function onEnter() {
  hoverTimer = setTimeout(() => {
    open.value = true
    loadCard()
  }, 300)
}

function onLeave() {
  if (hoverTimer) clearTimeout(hoverTimer)
  open.value = false
}

function toggleFollow() {
  if (!card.value?.follow_url) return
  router.post(card.value.follow_url, {}, {
    preserveScroll: true,
    onSuccess: () => {
      if (card.value) card.value.following = !card.value.following
    },
  })
}

onBeforeUnmount(() => {
  if (hoverTimer) clearTimeout(hoverTimer)
})
</script>

<template>
  <span class="relative inline-block" @mouseenter="onEnter" @mouseleave="onLeave">
    <slot />
    <div
      v-if="open"
      class="absolute left-0 top-full z-50 mt-1 w-64 rounded-lg border bg-popover p-3 text-sm shadow-lg"
    >
      <div v-if="loading && !card" class="text-muted-foreground">{{ t('common.loading') }}</div>
      <template v-else-if="card">
        <div class="flex items-center gap-2">
          <img :src="card.avatar_url" :alt="card.username" class="h-10 w-10 rounded-full" />
          <div class="min-w-0">
            <p class="font-medium">{{ card.display_name || card.username }}</p>
            <p class="text-xs text-muted-foreground">
              @{{ card.username }} · {{ card.trust_name }}
              <span v-if="card.online" class="ml-1 text-green-600">{{ t('components.userHover.online') }}</span>
              <span v-if="card.ingame_online && card.ingame_server" class="ml-1 text-emerald-600">{{ t('components.userHover.ingameOn', { server: card.ingame_server }) }}</span>
            </p>
          </div>
        </div>
        <p v-if="card.bio" class="mt-2 line-clamp-2 text-xs text-muted-foreground">{{ card.bio }}</p>
        <p class="mt-2 text-xs text-muted-foreground">
          {{ t('components.userHover.posts', { count: card.posts_count }) }}<span v-if="card.likes_received != null">{{ t('components.userHover.likes', { count: card.likes_received }) }}</span> · {{ t('components.userHover.memberSince', { date: card.member_since }) }}
          <span v-if="card.last_seen_at && !card.online">{{ t('components.userHover.lastSeen', { date: card.last_seen_at }) }}</span>
        </p>
        <div v-if="card.memberships?.length" class="mt-2 flex flex-wrap gap-1">
          <span
            v-for="membership in card.memberships"
            :key="membership.slug"
            class="rounded border px-1.5 py-0.5 text-[10px] font-medium"
            :style="membership.color ? { borderColor: membership.color, color: membership.color } : undefined"
          >
            {{ membership.icon ? `${membership.icon} ` : '' }}{{ membership.name }}
          </span>
        </div>
        <div v-if="card.badges.length" class="mt-2 flex flex-wrap gap-1">
          <span
            v-for="badge in card.badges"
            :key="badge.name"
            class="rounded border px-1.5 py-0.5 text-[10px]"
            :style="badge.color ? { borderColor: badge.color, color: badge.color } : undefined"
            :title="badge.granted_at ? `${badge.name} · ${badge.granted_at}` : badge.name"
          >
            {{ badge.icon ? `${badge.icon} ` : '' }}{{ badge.name }}
            <span v-if="badge.granted_at" class="opacity-70">· {{ badge.granted_at }}</span>
          </span>
        </div>
        <div class="mt-3 flex flex-wrap gap-2">
          <Link :href="card.profile_url" class="text-xs text-primary hover:underline">{{ t('components.userHover.viewProfile') }}</Link>
          <Link v-if="card.message_url" :href="card.message_url" class="text-xs text-primary hover:underline">{{ t('components.userHover.sendMessage') }}</Link>
          <button
            v-if="card.follow_url"
            type="button"
            class="text-xs text-primary hover:underline"
            @click="toggleFollow"
          >
            {{ card.following ? t('components.userHover.unfollow') : t('components.userHover.follow') }}
          </button>
        </div>
      </template>
    </div>
  </span>
</template>
