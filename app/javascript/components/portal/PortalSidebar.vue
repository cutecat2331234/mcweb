<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Link } from '@inertiajs/vue3'
import { MessageSquare, ShoppingBag, ExternalLink, Home, X } from '@lucide/vue'
import { routes } from '@/lib/routes'
import { usePortalNav, type PortalNavOptions } from '@/lib/usePortalNav'
import PortalNavGroupSection from '@/components/portal/PortalNavGroupSection.vue'
import Button from '@/components/ui/Button.vue'
import { cn } from '@/lib/utils'
import { useActiveTemplate } from '@/lib/useActiveTemplate'
import { useFeatureFlags } from '@/lib/useFeatureFlags'

const props = defineProps<PortalNavOptions & { class?: string; onNavigate?: () => void; showClose?: boolean }>()

const { features, showPortalSectionTabs, portalSectionGridClass } = useFeatureFlags()

const navOptions = computed(() => ({
  loggedIn: props.loggedIn,
  forumUnread: props.forumUnread,
  forumAssigned: props.forumAssigned,
  messagesUnread: props.messagesUnread,
  cart: props.cart,
}))

const { navGroups, isActive, isSectionActive, currentPath } = usePortalNav(navOptions)
const { activeTemplate } = useActiveTemplate()

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
        <span class="truncate">McWeb</span>
      </Link>
      <Button
        v-if="showClose"
        variant="ghost"
        size="icon"
        class="shrink-0 text-sidebar-foreground/70 lg:hidden"
        type="button"
        aria-label="关闭菜单"
        @click="onNavigate?.()"
      >
        <X class="h-5 w-5" />
      </Button>
    </div>

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
          论坛
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
          商城
        </Link>
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
        <span class="flex-1">返回官网</span>
        <ExternalLink class="h-3.5 w-3.5 shrink-0 opacity-50 transition-all group-hover:opacity-80" />
      </Link>
    </div>
  </aside>
</template>
