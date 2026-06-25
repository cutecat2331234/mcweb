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

defineProps<{
  staff: Array<{
    username: string
    display_name: string | null
    avatar_url: string
    profile_url: string
    title: string | null
    modules: string[]
    online: boolean
    last_seen_at: string | null
  }>
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.staff.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.staff.title')" :subtitle="t('forum.staff.subtitle')" />

  <div v-if="staff.length" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
    <Link
      v-for="member in staff"
      :key="member.username"
      :href="member.profile_url"
      class="flex items-center gap-3 rounded-lg border p-3 hover:bg-muted/50"
    >
      <div class="relative shrink-0">
        <img :src="member.avatar_url" :alt="member.username" class="h-12 w-12 rounded-full" />
        <span
          v-if="member.online"
          class="absolute bottom-0 right-0 h-3 w-3 rounded-full border-2 border-background bg-emerald-500"
          :title="t('forum.staff.online')"
        />
      </div>
      <div class="min-w-0 flex-1">
        <p class="truncate font-medium">{{ member.display_name || member.username }}</p>
        <p v-if="member.title" class="truncate text-xs text-muted-foreground">{{ member.title }}</p>
        <div class="mt-1 flex flex-wrap gap-1">
          <Badge v-for="mod in member.modules" :key="mod" variant="secondary" class="text-[10px]">{{ mod }}</Badge>
        </div>
      </div>
    </Link>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('forum.staff.empty') }}</p>
</template>
