<script setup lang="ts">
import { onBeforeUnmount, onMounted, nextTick, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import Button from '@/components/ui/Button.vue'
import { beginCommunityRelationshipMutation, finishCommunityRelationshipMutation } from '@/lib/communityRelationshipMutation'

const { t } = useI18n()

const props = withDefaults(defineProps<{
  username: string
  cardUrl: string
  /** When true, clicking the trigger pins the card open (outside-click / Esc closes). */
  pinnable?: boolean
  /** When true, the wrapper is an inert passthrough: no hover, no click, no card. */
  disabled?: boolean
}>(), {
  pinnable: false,
  disabled: false,
})

export interface UserCardData {
  username: string
  display_name: string | null
  avatar_url: string
  profile_url: string
  trust_level: number
  trust_name: string
  posts_count: number
  likes_received?: number
  trophy_points?: number
  bio?: string | null
  member_since: string
  last_seen_at?: string | null
  online?: boolean
  badges: Array<{ name: string; icon: string | null; color: string | null; granted_at?: string }>
  groups?: Array<{ name: string; color: string | null; banner: string | null }>
  memberships?: Array<{ name: string; slug: string; color?: string | null; icon?: string | null; expires_label?: string; permanent?: boolean }>
  message_url: string | null
  follow_url?: string | null
  following?: boolean
  ingame_online?: boolean
  ingame_server?: string | null
  last_seen_ingame_at?: string | null
}

const open = ref(false)
const pinned = ref(false)
const loading = ref(false)
const followProcessing = ref(false)
const card = ref<UserCardData | null>(null)
const triggerRef = ref<HTMLElement | null>(null)
const cardRef = ref<HTMLElement | null>(null)
const cardStyle = ref<Record<string, string>>({ top: '0px', left: '0px' })
let hoverTimer: ReturnType<typeof setTimeout> | null = null
let closeTimer: ReturnType<typeof setTimeout> | null = null

async function loadCard() {
  if (card.value || loading.value || !props.cardUrl) return
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

async function reloadCard() {
  card.value = null
  await loadCard()
}

function clearHoverTimer() {
  if (hoverTimer) { clearTimeout(hoverTimer); hoverTimer = null }
}
function clearCloseTimer() {
  if (closeTimer) { clearTimeout(closeTimer); closeTimer = null }
}

async function reallyOpen() {
  open.value = true
  loadCard()
  await nextTick()
  updatePosition()
}

function onEnter() {
  if (props.disabled) return
  clearCloseTimer()
  if (open.value) return
  clearHoverTimer()
  hoverTimer = setTimeout(() => { reallyOpen() }, 300)
}

function onLeave() {
  if (props.disabled) return
  clearHoverTimer()
  scheduleClose()
}

function scheduleClose() {
  clearCloseTimer()
  closeTimer = setTimeout(() => {
    if (!pinned.value) open.value = false
  }, 150)
}

function onCardEnter() { clearCloseTimer() }
function onCardLeave() { if (!pinned.value) scheduleClose() }

function togglePin() {
  clearHoverTimer()
  clearCloseTimer()
  pinned.value = !pinned.value
  if (pinned.value) reallyOpen()
  else { open.value = false }
}

function onClick(event: MouseEvent) {
  if (props.disabled || !props.pinnable) return
  // Keyboard-synthesized click (Enter/Space on the anchor) reports detail === 0:
  // the keydown handler already toggled, so only cancel the anchor's navigation.
  if (event.detail === 0) {
    event.preventDefault()
    return
  }
  // Let modifier / middle clicks fall through so the browser opens the profile
  // in a new tab (the trigger is a real anchor).
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button === 1) return
  event.preventDefault()
  togglePin()
}

function onKeydown(event: KeyboardEvent) {
  if (props.disabled) return
  if (event.key === 'Escape') {
    if (open.value) {
      event.stopPropagation()
      pinned.value = false
      open.value = false
    }
    return
  }
  if (!props.pinnable) return
  if (event.key === 'Enter' || event.key === ' ' || event.key === 'Spacebar') {
    event.preventDefault()
    togglePin()
  }
}

function onDocPointer(event: Event) {
  if (!pinned.value) return
  const target = event.target as Node
  if (triggerRef.value?.contains(target)) return
  if (cardRef.value?.contains(target)) return
  pinned.value = false
  open.value = false
}

function updatePosition() {
  const el = triggerRef.value
  if (!el) return
  const rect = el.getBoundingClientRect()
  const cardWidth = 256 // w-64
  let left = rect.left
  if (left + cardWidth > window.innerWidth - 8) left = window.innerWidth - cardWidth - 8
  if (left < 8) left = 8
  const estHeight = cardRef.value?.offsetHeight || 240
  let top = rect.bottom + 4
  if (top + estHeight > window.innerHeight - 8 && rect.top - estHeight - 4 >= 8) {
    top = rect.top - estHeight - 4
  }
  cardStyle.value = { top: `${top}px`, left: `${left}px` }
}

function onScrollResize() {
  if (open.value) updatePosition()
}

function toggleFollow() {
  if (!card.value?.follow_url) return

  const mutation = beginCommunityRelationshipMutation(followProcessing, card.value.following === true)
  if (!mutation) return
  const url = card.value.follow_url
  const options = {
    preserveScroll: true,
    preserveState: true,
    onSuccess: () => { void reloadCard() },
    onFinish: () => finishCommunityRelationshipMutation(followProcessing),
  }
  if (mutation.method === 'put') router.put(url, {}, options)
  else router.delete(url, options)
}

onMounted(() => {
  document.addEventListener('pointerdown', onDocPointer, true)
  window.addEventListener('scroll', onScrollResize, true)
  window.addEventListener('resize', onScrollResize)
})

onBeforeUnmount(() => {
  clearHoverTimer()
  clearCloseTimer()
  document.removeEventListener('pointerdown', onDocPointer, true)
  window.removeEventListener('scroll', onScrollResize, true)
  window.removeEventListener('resize', onScrollResize)
})
</script>

<template>
  <span
    ref="triggerRef"
    class="relative inline-block"
    @mouseenter="onEnter"
    @mouseleave="onLeave"
    @click="onClick"
    @keydown="onKeydown"
  >
    <slot :open="open" :pinned="pinned" />
    <Teleport to="body">
      <div
        v-if="open && (loading || card)"
        ref="cardRef"
        class="fixed z-[60] w-64 rounded-lg border bg-popover p-3 text-sm shadow-lg"
        :style="cardStyle"
        role="dialog"
        @mouseenter="onCardEnter"
        @mouseleave="onCardLeave"
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
            {{ t('components.userHover.posts', { count: card.posts_count }) }}<span v-if="card.likes_received != null">{{ t('components.userHover.likes', { count: card.likes_received }) }}</span><span v-if="card.trophy_points">{{ t('components.userHover.trophies', { count: card.trophy_points }) }}</span> · {{ t('components.userHover.memberSince', { date: card.member_since }) }}
            <span v-if="card.last_seen_at && !card.online">{{ t('components.userHover.lastSeen', { date: card.last_seen_at }) }}</span>
          </p>
          <div v-if="card.groups?.length" class="mt-2 flex flex-wrap gap-1">
            <span
              v-for="group in card.groups"
              :key="group.name"
              class="rounded-full px-2 py-0.5 text-[10px] font-medium"
              :style="group.color ? { backgroundColor: group.color + '22', color: group.color } : undefined"
              :class="group.color ? '' : 'bg-muted text-muted-foreground'"
            >
              {{ group.name }}
            </span>
          </div>
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
            <Button
              v-if="card.follow_url"
              type="button"
              variant="link"
              size="sm"
              :disabled="followProcessing || loading"
              @click.stop="toggleFollow"
            >
              {{ card.following ? t('components.userHover.unfollow') : t('components.userHover.follow') }}
            </Button>
          </div>
        </template>
      </div>
    </Teleport>
  </span>
</template>
