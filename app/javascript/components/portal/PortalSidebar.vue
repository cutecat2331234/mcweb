<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Link, usePage } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { MessageSquare, ShoppingBag, ExternalLink, Home, X } from '@lucide/vue'
import { routes } from '@/lib/routes'
import { usePortalNav, type PortalNavOptions } from '@/lib/usePortalNav'
import PortalNavGroupSection from '@/components/portal/PortalNavGroupSection.vue'
import Button from '@/components/ui/Button.vue'
import { cn } from '@/lib/utils'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useFeatureFlags } from '@/lib/useFeatureFlags'

const props = defineProps<PortalNavOptions & { class?: string; onNavigate?: () => void; showClose?: boolean }>()
const { t } = useI18n()

const { features, showPortalSectionTabs, portalSectionGridClass } = useFeatureFlags()

const navOptions = computed(() => ({
  loggedIn: props.loggedIn,
  forumUnread: props.forumUnread,
  forumNew: props.forumNew,
  forumAssigned: props.forumAssigned,
  forumModerationPending: props.forumModerationPending,
  messagesUnread: props.messagesUnread,
  cart: props.cart,
}))

const { navGroups, isActive, isSectionActive, currentPath } = usePortalNav(navOptions)
const { activeTemplate, portalSidebarExtraSlot } = useActiveTemplate()
const page = usePage()
const minecraftServers = computed(() => page.props.minecraft_servers as Array<{ name: string; online: number; max: number; status: string; anomaly?: boolean }> | undefined)
const minecraftHealth = computed(() => page.props.minecraft_health as { alert?: boolean; stale_nodes?: number; process_mismatch?: number; maintenance?: number } | undefined)

const serverStatusLabels: Record<string, string> = {
  online: 'portal.serverStatusOnline',
  offline: 'portal.serverStatusOffline',
  maintenance: 'portal.serverStatusMaintenance',
}

function serverStatusLabel(status: string) {
  const key = serverStatusLabels[status]
  return key ? t(key) : status
}

const STORAGE_KEY = 'mc-portal-nav-expanded'

function loadExpanded(): Record<string, boolean> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return JSON.parse(raw) as Record<string, boolean>
  } catch {
    /* ignore */
  }
  return {}
}

const expandedGroups = ref<Record<string, boolean>>(loadExpanded())

watch(
  navGroups,
  (groups) => {
    for (const group of groups) {
      if (expandedGroups.value[group.key] === undefined) {
        expandedGroups.value[group.key] = group.defaultExpanded ?? true
      }
    }
  },
  { immediate: true },
)

function toggleGroup(key: string) {
  expandedGroups.value[key] = !expandedGroups.value[key]
  persistExpanded()
}

function isGroupExpanded(key: string, defaultExpanded: boolean) {
  return expandedGroups.value[key] ?? defaultExpanded
}

function persistExpanded() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(expandedGroups.value))
}

watch(
  [currentPath, navGroups],
  () => {
    for (const group of navGroups.value) {
      if (group.items.some((item) => isActive(item.href))) {
        if (!expandedGroups.value[group.key]) {
          expandedGroups.value[group.key] = true
          persistExpanded()
        }
      }
    }
  },
  { immediate: true },
)
</script>

<template>
  <aside
    :class="cn(
      'flex h-full w-64 shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground',
      props.class,
    )"
  >
    <div class="flex h-14 items-center gap-2 border-b border-sidebar-border/50 px-4">
      <Link
        :href="routes.home"
        class="flex min-w-0 flex-1 items-center gap-2.5 font-semibold tracking-tight text-sidebar-foreground no-underline"
        @click="onNavigate?.()"
      >
        <img v-if="activeTemplate?.logoUrl" :src="activeTemplate.logoUrl" alt="" class="h-8 w-auto shrink-0">
        <span v-else class="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-primary/10 p-1.5 text-base">⛏</span>
        <span class="truncate">{{ t('portal.brand') }}</span>
      </Link>
      <Button
        v-if="showClose"
        variant="ghost"
        size="icon"
        class="shrink-0 text-sidebar-foreground/70 lg:hidden"
        type="button"
        :aria-label="t('common.close')"
        @click="onNavigate?.()"
      >
        <X class="h-5 w-5" />
      </Button>
    </div>

    <div v-if="portalSidebarExtraSlot" class="px-3 pt-3 text-sm text-sidebar-foreground/80" v-html="portalSidebarExtraSlot" />

    <div v-if="showPortalSectionTabs" class="p-3">
      <div
        :class="cn(
          'grid gap-1 rounded-lg border border-sidebar-border/40 bg-sidebar-accent/30 p-1',
          portalSectionGridClass,
        )"
      >
        <Link
          v-if="features.forum"
          :href="routes.forum"
          :class="cn(
            'flex items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-all duration-150 active:scale-[0.98]',
            isSectionActive('forum')
              ? 'bg-background/80 text-sidebar-foreground shadow-sm'
              : 'text-sidebar-foreground/65 hover:bg-background/40 hover:text-sidebar-foreground',
          )"
          @click="onNavigate?.()"
        >
          <MessageSquare class="h-4 w-4" />
          {{ t('nav.forum') }}
        </Link>
        <Link
          v-if="features.store"
          :href="routes.store"
          :class="cn(
            'flex items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-all duration-150 active:scale-[0.98]',
            isSectionActive('store')
              ? 'bg-background/80 text-sidebar-foreground shadow-sm'
              : 'text-sidebar-foreground/65 hover:bg-background/40 hover:text-sidebar-foreground',
          )"
          @click="onNavigate?.()"
        >
          <ShoppingBag class="h-4 w-4" />
          {{ t('nav.store') }}
        </Link>
      </div>
    </div>

    <div v-if="features.minecraft && minecraftServers?.length" class="px-3 pb-3">
      <p class="mb-2 flex items-center gap-2 px-1 text-xs font-medium uppercase tracking-wide text-sidebar-foreground/50">
        {{ t('portal.serverStatus') }}
        <span
          v-if="minecraftHealth?.alert"
          class="rounded bg-amber-500/20 px-1.5 py-0.5 text-[10px] font-semibold normal-case text-amber-700 dark:text-amber-300"
          :title="t('portal.serverAnomalyHint')"
        >!</span>
      </p>
      <div class="space-y-2">
        <div
          v-for="server in minecraftServers"
          :key="server.name"
          class="rounded-lg border border-sidebar-border/40 bg-sidebar-accent/20 px-3 py-2 text-xs"
          :class="server.anomaly || server.status === 'maintenance' ? 'border-amber-500/40' : ''"
        >
          <div class="flex items-center gap-1 font-medium text-sidebar-foreground">
            {{ server.name }}
            <span v-if="server.anomaly || server.status === 'maintenance'" class="text-amber-600">⚠</span>
          </div>
          <div class="text-sidebar-foreground/70">{{ server.online }}/{{ server.max }} {{ t('portal.online') }}{{ t('common.colon') }} {{ serverStatusLabel(server.status) }}</div>
        </div>
      </div>
    </div>

    <nav class="flex-1 space-y-3 overflow-y-auto px-3 pb-4">
      <PortalNavGroupSection
        v-for="group in navGroups"
        :key="group.key"
        :group="group"
        :expanded="isGroupExpanded(group.key, group.defaultExpanded ?? true)"
        :is-active="isActive"
        @toggle="toggleGroup(group.key)"
        @navigate="onNavigate?.()"
      />
    </nav>

    <div class="mt-auto border-t border-sidebar-border/50 p-3">
      <Link
        :href="routes.home"
        class="group flex items-center gap-2.5 rounded-lg border border-sidebar-border/30 px-3 py-2.5 text-sm text-sidebar-foreground/70 transition-all duration-150 hover:border-sidebar-border/60 hover:bg-sidebar-accent/30 hover:text-sidebar-foreground active:scale-[0.99]"
        @click="onNavigate?.()"
      >
        <Home class="h-4 w-4 shrink-0 opacity-70 transition-colors group-hover:opacity-100" />
        <span class="flex-1">{{ t('portal.backToWebsite') }}</span>
        <ExternalLink class="h-3.5 w-3.5 shrink-0 opacity-50 transition-all group-hover:opacity-80" />
      </Link>
    </div>
  </aside>
</template>
