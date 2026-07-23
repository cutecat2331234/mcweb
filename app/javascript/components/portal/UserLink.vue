<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import UserHoverCard from '@/components/portal/UserHoverCard.vue'
import Avatar from '@/components/ui/Avatar.vue'
import { appPrefix } from '@/lib/routes'

/**
 * UserLink — one component for every place a username/avatar appears.
 *
 * Renders the avatar and/or name and wraps it in the XenForo-style user card
 * (hover to preview, click to pin). The card data is lazy-loaded from `cardUrl`.
 *
 * The card endpoint always lives at `<profile_url>/card`, so a call site only
 * needs ONE of: an explicit `cardUrl`, a `username` (→ /forum/users/:username/card),
 * or a `profileUrl` (→ `profileUrl` + '/card'). Any of them unlocks the card.
 *
 * Usage:
 *   <UserLink :user="author" variant="inline" />
 *   <UserLink :username="row.username" :avatar-url="row.avatar_url" variant="avatar" size="xs" />
 *   <UserLink :username="u" :profile-url="url" :display-name="name" />
 */

interface UserLike {
  username?: string | null
  display_name?: string | null
  displayName?: string | null
  name?: string | null
  avatar_url?: string | null
  avatarUrl?: string | null
  profile_url?: string | null
  profileUrl?: string | null
  url?: string | null
  card_url?: string | null
  cardUrl?: string | null
}

const props = withDefaults(defineProps<{
  /** A user-ish object; individual props below override its fields when both are given. */
  user?: UserLike | null
  username?: string | null
  displayName?: string | null
  avatarUrl?: string | null
  profileUrl?: string | null
  cardUrl?: string | null
  /** name = username only, avatar = avatar only, inline = avatar + name. */
  variant?: 'name' | 'avatar' | 'inline'
  /** Avatar size preset (overridable with `avatarClass`). */
  size?: 'xs' | 'sm' | 'md' | 'lg' | 'xl'
  /** Show a muted `@username` after the name. */
  handle?: boolean
  /** Enable the hover/click card (default true). */
  card?: boolean
  /** Clicking the trigger pins the card open (default true). */
  pinnable?: boolean
  /** Extra classes for the trigger container (e.g. `font-medium hover:underline`). */
  linkClass?: string
  /** Extra classes for the name text. */
  nameClass?: string
  /** Extra classes for the avatar element. */
  avatarClass?: string
}>(), {
  variant: 'name',
  size: 'md',
  handle: false,
  card: true,
  pinnable: true,
})

const u = computed<UserLike>(() => props.user || {})

const username = computed(() => props.username ?? u.value.username ?? null)

const displayName = computed(
  () => props.displayName ?? u.value.displayName ?? u.value.display_name ?? u.value.name ?? username.value ?? '',
)

const avatarUrl = computed(() => props.avatarUrl ?? u.value.avatarUrl ?? u.value.avatar_url ?? null)

const profileUrl = computed(() => {
  const explicit = props.profileUrl ?? u.value.profileUrl ?? u.value.profile_url ?? u.value.url
  if (explicit) return explicit
  if (username.value) return `${appPrefix}/forum/users/${username.value}`
  return null
})

const cardUrl = computed(() => {
  const explicit = props.cardUrl ?? u.value.cardUrl ?? u.value.card_url
  if (explicit) return explicit
  if (username.value) return `${appPrefix}/forum/users/${username.value}/card`
  if (profileUrl.value) return `${profileUrl.value}/card`
  return null
})

const hoverEnabled = computed(() => props.card && !!cardUrl.value)

// UserHoverCard wants a non-null label for its aria/alt text.
const cardUsername = computed(() => username.value || displayName.value || '')

const avatarSizeClass = computed(() => ({
  xs: 'h-5 w-5',
  sm: 'h-7 w-7',
  md: 'h-8 w-8',
  lg: 'h-10 w-10',
  xl: 'h-12 w-12',
}[props.size]))

const linkTag = computed(() => {
  if (!profileUrl.value) return 'span'
  // When the card is active, use a plain <a> (not an Inertia <Link>). Inertia's
  // <Link> runs its own click handler (router.visit) on the anchor before our
  // wrapper's bubble-phase handler, so preventDefault there cannot stop the
  // navigation — a plain left-click would both pin AND navigate. A native anchor
  // has no JS handler: its navigation is a default action the browser only
  // performs after dispatch, so our preventDefault cleanly cancels it (pin only).
  // Modifier / middle clicks still open the profile in a new tab natively.
  return hoverEnabled.value ? 'a' : Link
})

const containerClass = computed(() => [
  props.variant === 'name' ? 'inline' : 'inline-flex items-center gap-2 align-middle',
  hoverEnabled.value && !profileUrl.value ? 'cursor-pointer' : '',
  props.linkClass,
])
</script>

<template>
  <UserHoverCard
    v-slot="{ open }"
    :username="cardUsername"
    :card-url="cardUrl || ''"
    :pinnable="pinnable"
    :disabled="!hoverEnabled"
  >
    <component
      :is="linkTag"
      :href="profileUrl || undefined"
      :class="containerClass"
      :tabindex="!profileUrl && hoverEnabled ? 0 : undefined"
      :role="!profileUrl && hoverEnabled ? 'button' : undefined"
      :aria-haspopup="hoverEnabled ? 'dialog' : undefined"
      :aria-expanded="hoverEnabled ? open : undefined"
    >
      <Avatar
        v-if="variant !== 'name'"
        :class="[avatarSizeClass, avatarClass]"
        :fallback="displayName"
      >
        <img
          v-if="avatarUrl"
          :src="avatarUrl"
          :alt="displayName"
          class="h-full w-full object-cover"
        />
      </Avatar>
      <span v-if="variant !== 'avatar'" :class="nameClass">
        <slot>{{ displayName }}</slot>
      </span>
      <span
        v-if="handle && username && variant !== 'avatar'"
        class="text-xs font-normal text-muted-foreground"
      >@{{ username }}</span>
    </component>
  </UserHoverCard>
</template>
