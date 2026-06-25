<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import Badge from '@/components/ui/Badge.vue'
import { cn } from '@/lib/utils'
import {
  Activity,
  ArrowDown,
  Award,
  Ban,
  Bell,
  Bookmark,
  CircleDot,
  Eye,
  FileText,
  Flame,
  Gift,
  Heart,
  History,
  Home,
  Inbox,
  LayoutGrid,
  List,
  Mail,
  MapPin,
  Package,
  Search,
  Settings,
  Shield,
  ShoppingBag,
  ShoppingCart,
  SlidersHorizontal,
  Sparkles,
  Tag,
  UserMinus,
  UserPlus,
  Users,
  Volume2,
  Wallet,
} from '@lucide/vue'
import type { Component } from 'vue'
import type { PortalNavItem } from '@/lib/usePortalNav'

const iconMap: Record<string, Component> = {
  'layout-grid': LayoutGrid,
  sparkles: Sparkles,
  flame: Flame,
  activity: Activity,
  search: Search,
  tag: Tag,
  award: Award,
  users: Users,
  eye: Eye,
  bookmark: Bookmark,
  'circle-dot': CircleDot,
  list: List,
  'user-plus': UserPlus,
  inbox: Inbox,
  mail: Mail,
  'file-text': FileText,
  settings: Settings,
  shield: Shield,
  ban: Ban,
  'user-minus': UserMinus,
  'volume-off': Volume2,
  'shopping-bag': ShoppingBag,
  sliders: SlidersHorizontal,
  history: History,
  package: Package,
  heart: Heart,
  'shopping-cart': ShoppingCart,
  'map-pin': MapPin,
  wallet: Wallet,
  gift: Gift,
  bell: Bell,
  'arrow-down': ArrowDown,
  home: Home,
}

defineProps<{
  item: PortalNavItem
  active?: boolean
  compact?: boolean
}>()

const emit = defineEmits<{ navigate: [] }>()
</script>

<template>
  <Link
    :href="item.href"
    @click="emit('navigate')"
    :class="cn(
      'group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-all duration-150 active:scale-[0.99]',
      active
        ? 'relative bg-sidebar-accent text-sidebar-accent-foreground before:absolute before:left-0 before:top-1/2 before:h-5 before:w-0.5 before:-translate-y-1/2 before:rounded-full before:bg-primary'
        : 'text-sidebar-foreground/75 hover:bg-sidebar-accent/50 hover:text-sidebar-accent-foreground',
      compact && 'px-2.5 py-2',
    )"
  >
    <component
      :is="iconMap[item.icon || '']"
      v-if="item.icon && iconMap[item.icon]"
      class="h-4 w-4 shrink-0 opacity-70 group-hover:opacity-100"
      :class="active && 'opacity-100'"
    />
    <span class="truncate">{{ item.label }}</span>
    <Badge
      v-if="item.badge && item.badge > 0"
      variant="danger"
      class="ml-auto h-5 min-w-5 px-1.5 text-[10px] font-semibold"
    >
      {{ item.badge > 99 ? '99+' : item.badge }}
    </Badge>
  </Link>
</template>
