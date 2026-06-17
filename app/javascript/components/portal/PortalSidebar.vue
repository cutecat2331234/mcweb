<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { MessageSquare, ShoppingBag, ExternalLink, Home, X } from '@lucide/vue'
import { routes } from '@/lib/routes'
import { usePortalNav, type PortalNavOptions } from '@/lib/usePortalNav'
import PortalNavLink from '@/components/portal/PortalNavLink.vue'
import Button from '@/components/ui/Button.vue'
import { cn } from '@/lib/utils'
import { useActiveTemplate } from '@/lib/useActiveTemplate'

const props = defineProps<PortalNavOptions & { class?: string; onNavigate?: () => void; showClose?: boolean }>()

const navOptions = computed(() => ({
  loggedIn: props.loggedIn,
  forumUnread: props.forumUnread,
  forumAssigned: props.forumAssigned,
  messagesUnread: props.messagesUnread,
  cart: props.cart,
}))

const { navGroups, isActive, isSectionActive } = usePortalNav(navOptions)
const { activeTemplate } = useActiveTemplate()
</script>

<template>
  <aside
    :class="cn(
      'flex h-full w-64 shrink-0 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground',
      props.class,
    )"
  >
    <div class="flex h-14 items-center gap-2 border-b border-sidebar-border px-4">
      <Link
        :href="routes.home"
        class="flex min-w-0 flex-1 items-center gap-2.5 font-semibold tracking-tight text-sidebar-foreground no-underline"
        @click="onNavigate?.()"
      >
        <img v-if="activeTemplate?.logoUrl" :src="activeTemplate.logoUrl" alt="" class="h-8 w-auto shrink-0">
        <span class="truncate">McWeb</span>
      </Link>
      <Button
        v-if="showClose"
        variant="ghost"
        size="icon"
        class="shrink-0 lg:hidden"
        type="button"
        aria-label="关闭菜单"
        @click="onNavigate?.()"
      >
        <X class="h-5 w-5" />
      </Button>
    </div>

    <div class="p-3">
      <div class="grid grid-cols-2 gap-1 rounded-lg bg-sidebar-accent/50 p-1">
        <Link
          :href="routes.forum"
          :class="cn(
            'flex items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-all',
            isSectionActive('forum')
              ? 'bg-sidebar text-sidebar-foreground shadow-sm'
              : 'text-sidebar-foreground/70 hover:text-sidebar-foreground',
          )"
          @click="onNavigate?.()"
        >
          <MessageSquare class="h-4 w-4" />
          论坛
        </Link>
        <Link
          :href="routes.store"
          :class="cn(
            'flex items-center justify-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-all',
            isSectionActive('store')
              ? 'bg-sidebar text-sidebar-foreground shadow-sm'
              : 'text-sidebar-foreground/70 hover:text-sidebar-foreground',
          )"
          @click="onNavigate?.()"
        >
          <ShoppingBag class="h-4 w-4" />
          商城
        </Link>
      </div>
    </div>

    <nav class="flex-1 space-y-6 overflow-y-auto px-3 pb-4">
      <div v-for="group in navGroups" :key="group.key">
        <p class="mb-2 px-3 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/50">
          {{ group.label }}
        </p>
        <div class="space-y-0.5">
          <PortalNavLink
            v-for="item in group.items"
            :key="item.href"
            :item="item"
            :active="isActive(item.href)"
            @navigate="onNavigate?.()"
          />
        </div>
      </div>
    </nav>

    <div class="mt-auto border-t border-sidebar-border p-3">
      <Link
        :href="routes.home"
        class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent/60 hover:text-sidebar-foreground"
        @click="onNavigate?.()"
      >
        <Home class="h-4 w-4" />
        返回官网
        <ExternalLink class="ml-auto h-3.5 w-3.5 opacity-50" />
      </Link>
    </div>
  </aside>
</template>
