<script setup lang="ts">
import { ref, computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Input from '@/components/ui/Input.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  members: Array<{
    username: string
    display_name: string | null
    avatar_url: string
    profile_url: string
    last_seen_at: string | null
    online: boolean
    posts_count: number
    likes_received: number
    reviews_count: number
    purchases_count: number
    trust_level: number
    trust_name: string
    member_since: string
  }>
  pagination: PaginationMeta
  query: string
  sort: string
  trustLevel?: string
}>()

const searchQuery = ref(props.query)

const sortOptions = computed(() => [
  { value: 'active', label: t('forum.members.sortActive') },
  { value: 'online', label: t('forum.members.sortOnline') },
  { value: 'joined', label: t('forum.members.sortJoined') },
  { value: 'posts', label: t('forum.members.sortPosts') },
  { value: 'likes', label: t('forum.members.sortLikes') },
  { value: 'reviews', label: t('forum.members.sortReviews') },
  { value: 'purchases', label: t('forum.members.sortPurchases') },
])

const trustLevelOptions = computed(() => [
  { value: '', label: t('forum.members.allTrustLevels') },
  { value: '0', label: t('forum.members.tl0') },
  { value: '1', label: t('forum.members.tl1') },
  { value: '2', label: t('forum.members.tl2') },
  { value: '3', label: t('forum.members.tl3') },
  { value: '4', label: t('forum.members.tl4') },
])

function search() {
  router.get(routes.forumMembers, {
    q: searchQuery.value || undefined,
    sort: props.sort !== 'active' ? props.sort : undefined,
  }, { preserveState: true })
}

function changeSort(value: string) {
  router.get(routes.forumMembers, {
    q: searchQuery.value || undefined,
    sort: value !== 'active' ? value : undefined,
    trust_level: props.trustLevel || undefined,
  }, { preserveState: true })
}

function changeTrustLevel(value: string) {
  router.get(routes.forumMembers, {
    q: searchQuery.value || undefined,
    sort: props.sort !== 'active' ? props.sort : undefined,
    trust_level: value || undefined,
  }, { preserveState: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.members.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.members.title')" :subtitle="t('forum.members.subtitle')" />

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <form class="flex flex-1 gap-2" @submit.prevent="search">
      <Input v-model="searchQuery" :placeholder="t('forum.members.searchPlaceholder')" class="max-w-xs" />
      <Button type="submit" variant="outline">{{ t('forum.members.search') }}</Button>
    </form>
    <Select :model-value="sort" :options="sortOptions" size="sm" @update:model-value="changeSort" />
    <Select :model-value="trustLevel || ''" :options="trustLevelOptions" size="sm" @update:model-value="changeTrustLevel" />
    <Button as-child variant="outline" size="sm">
      <Link :href="routes.forumLeaderboard">{{ t('forum.members.leaderboardLink') }}</Link>
    </Button>
  </div>

  <div v-if="members.length" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="member in members"
      :key="member.username"
      :href="member.profile_url"
      class="flex items-center gap-3 rounded-lg border p-4 hover:bg-muted/50"
    >
      <img :src="member.avatar_url" :alt="member.username" class="h-12 w-12 rounded-full" />
      <div class="min-w-0">
        <p class="font-medium">
          {{ member.display_name || member.username }}
          <Badge v-if="member.online" class="ml-2 text-[10px]">{{ t('forum.members.online') }}</Badge>
        </p>
        <p class="text-xs text-muted-foreground">
          @{{ member.username }} · {{ member.trust_name }} · {{ t('forum.members.posts', { n: member.posts_count }) }} · {{ t('forum.members.likes', { n: member.likes_received }) }} · {{ t('forum.members.purchases', { n: member.purchases_count }) }}
        </p>
        <p class="text-xs text-muted-foreground">
          {{ t('forum.members.reviews', { n: member.reviews_count }) }} ·
          {{ member.last_seen_at ? t('forum.members.lastSeen', { at: member.last_seen_at }) : t('forum.members.joined', { at: member.member_since }) }}
        </p>
      </div>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('forum.members.empty') }}</p>

  <Pagination :pagination="pagination" :base-path="routes.forumMembers" />
</template>
