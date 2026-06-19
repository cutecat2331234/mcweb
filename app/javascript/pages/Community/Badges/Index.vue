<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

interface BadgeItem {
  name: string
  slug: string
  icon: string
  color: string
  description: string | null
  grant_rule_label: string
  users_count: number
  url: string
}

defineProps<{
  badges: BadgeItem[]
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.badges.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.badges.title')" :subtitle="t('forum.badges.subtitle')" />

  <div v-if="badges.length" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="badge in badges"
      :key="badge.slug"
      :href="badge.url"
      class="rounded-lg border p-4 transition-colors hover:bg-muted/50"
    >
      <div class="flex items-start gap-3">
        <span class="text-2xl" :style="{ color: badge.color }">{{ badge.icon }}</span>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold" :style="{ color: badge.color }">{{ badge.name }}</h2>
          <p v-if="badge.description" class="mt-1 text-sm text-muted-foreground">{{ badge.description }}</p>
          <div class="mt-2 flex flex-wrap gap-2">
            <Badge variant="secondary">{{ badge.grant_rule_label }}</Badge>
            <Badge variant="outline">{{ t('forum.badges.usersEarned', { count: badge.users_count }) }}</Badge>
          </div>
        </div>
      </div>
    </Link>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('forum.badges.empty') }}</p>
</template>
