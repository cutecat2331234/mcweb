<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

type MemberRow = { username: string; display_name: string | null; avatar_url: string; url: string; value: number | string }

defineProps<{
  metrics: Array<{ label: string; value: number | string }>
  topPosters: MemberRow[]
  mostReacted: MemberRow[]
  newestMembers: MemberRow[]
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.stats.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.stats.title')" :subtitle="t('forum.stats.subtitle')" />

  <div class="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <div v-for="m in metrics" :key="m.label" class="rounded-lg border p-4">
      <p class="text-sm text-muted-foreground">{{ m.label }}</p>
      <p class="mt-1 text-2xl font-semibold">{{ m.value }}</p>
    </div>
  </div>

  <div class="grid gap-8 lg:grid-cols-3">
    <section>
      <h2 class="mb-3 text-sm font-semibold">{{ t('forum.stats.topPosters') }}</h2>
      <ol class="space-y-2">
        <li v-for="(row, i) in topPosters" :key="row.username">
          <Link :href="row.url" class="flex items-center gap-2 rounded-lg border p-2 text-sm hover:bg-muted/50">
            <span class="w-5 shrink-0 text-center text-xs text-muted-foreground">{{ i + 1 }}</span>
            <img :src="row.avatar_url" :alt="row.username" class="h-7 w-7 rounded-full" />
            <span class="min-w-0 flex-1 truncate">{{ row.display_name || row.username }}</span>
            <span class="text-xs font-medium">{{ row.value }}</span>
          </Link>
        </li>
      </ol>
    </section>

    <section>
      <h2 class="mb-3 text-sm font-semibold">{{ t('forum.stats.mostReacted') }}</h2>
      <ol class="space-y-2">
        <li v-for="(row, i) in mostReacted" :key="row.username">
          <Link :href="row.url" class="flex items-center gap-2 rounded-lg border p-2 text-sm hover:bg-muted/50">
            <span class="w-5 shrink-0 text-center text-xs text-muted-foreground">{{ i + 1 }}</span>
            <img :src="row.avatar_url" :alt="row.username" class="h-7 w-7 rounded-full" />
            <span class="min-w-0 flex-1 truncate">{{ row.display_name || row.username }}</span>
            <span class="text-xs font-medium">{{ row.value }}</span>
          </Link>
        </li>
      </ol>
    </section>

    <section>
      <h2 class="mb-3 text-sm font-semibold">{{ t('forum.stats.newestMembers') }}</h2>
      <ol class="space-y-2">
        <li v-for="row in newestMembers" :key="row.username">
          <Link :href="row.url" class="flex items-center gap-2 rounded-lg border p-2 text-sm hover:bg-muted/50">
            <img :src="row.avatar_url" :alt="row.username" class="h-7 w-7 rounded-full" />
            <span class="min-w-0 flex-1 truncate">{{ row.display_name || row.username }}</span>
            <span class="text-xs text-muted-foreground">{{ row.value }}</span>
          </Link>
        </li>
      </ol>
    </section>
  </div>
</template>
