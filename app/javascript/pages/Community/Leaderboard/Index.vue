<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  entries: Array<{
    rank: number
    score: number
    username: string
    display_name: string | null
    avatar_url: string
    profile_url: string
    trust_level: number
    trust_name: string
  }>
  period: 'all' | 'week' | 'month'
  metric: 'posts' | 'likes'
}>()

function apply(next: { period?: string; metric?: string }) {
  const period = next.period ?? props.period
  const metric = next.metric ?? props.metric
  router.get(routes.forumLeaderboard, {
    period: period === 'all' ? undefined : period,
    metric: metric === 'posts' ? undefined : metric,
  }, { preserveState: true })
}

function medal(rank: number): string {
  if (rank === 1) return '🥇'
  if (rank === 2) return '🥈'
  if (rank === 3) return '🥉'
  return `#${rank}`
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.leaderboard.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.leaderboard.title')" :subtitle="t('forum.leaderboard.subtitle')" />

  <div class="mb-4 flex flex-wrap items-center gap-3">
    <div class="flex gap-1">
      <Button :variant="metric === 'posts' ? 'default' : 'outline'" size="sm" @click="apply({ metric: 'posts' })">{{ t('forum.leaderboard.metricPosts') }}</Button>
      <Button :variant="metric === 'likes' ? 'default' : 'outline'" size="sm" @click="apply({ metric: 'likes' })">{{ t('forum.leaderboard.metricLikes') }}</Button>
    </div>
    <div class="flex gap-1">
      <Button :variant="period === 'all' ? 'default' : 'outline'" size="sm" @click="apply({ period: 'all' })">{{ t('forum.leaderboard.periodAll') }}</Button>
      <Button :variant="period === 'week' ? 'default' : 'outline'" size="sm" @click="apply({ period: 'week' })">{{ t('forum.leaderboard.periodWeek') }}</Button>
      <Button :variant="period === 'month' ? 'default' : 'outline'" size="sm" @click="apply({ period: 'month' })">{{ t('forum.leaderboard.periodMonth') }}</Button>
    </div>
  </div>

  <ol v-if="entries.length" class="space-y-2">
    <li v-for="entry in entries" :key="entry.username">
      <Link :href="entry.profile_url" class="flex items-center gap-3 rounded-lg border p-3 hover:bg-muted/50">
        <span class="w-10 shrink-0 text-center text-lg font-semibold">{{ medal(entry.rank) }}</span>
        <img :src="entry.avatar_url" :alt="entry.username" class="h-10 w-10 rounded-full" />
        <div class="min-w-0 flex-1">
          <p class="font-medium">{{ entry.display_name || entry.username }}</p>
          <p class="text-xs text-muted-foreground">@{{ entry.username }} · {{ entry.trust_name }}</p>
        </div>
        <Badge variant="secondary">
          {{ entry.score }} {{ metric === 'likes' ? t('forum.leaderboard.unitLikes') : t('forum.leaderboard.unitPosts') }}
        </Badge>
      </Link>
    </li>
  </ol>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('forum.leaderboard.empty') }}</p>
</template>
