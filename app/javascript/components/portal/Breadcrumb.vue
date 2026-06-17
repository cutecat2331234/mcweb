<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { ChevronRight, Home } from '@lucide/vue'
import { cn } from '@/lib/utils'

export interface BreadcrumbItem {
  label: string
  href?: string
  current?: boolean
}

defineProps<{
  items: BreadcrumbItem[]
}>()
</script>

<template>
  <nav class="mb-6 flex flex-wrap items-center gap-1.5 text-sm text-muted-foreground" aria-label="Breadcrumb">
    <template v-for="(item, index) in items" :key="index">
      <ChevronRight v-if="index > 0" class="h-3.5 w-3.5 shrink-0 opacity-50" aria-hidden="true" />
      <span
        v-if="item.current || !item.href"
        :class="cn(
          'truncate',
          item.current ? 'font-medium text-foreground' : 'text-muted-foreground',
        )"
        :aria-current="item.current ? 'page' : undefined"
      >
        <Home v-if="index === 0 && item.label === '首页'" class="mr-1 inline h-3.5 w-3.5 -translate-y-px" />
        {{ item.label }}
      </span>
      <Link
        v-else
        :href="item.href"
        class="truncate transition-colors hover:text-foreground"
      >
        <Home v-if="index === 0 && item.label === '首页'" class="mr-1 inline h-3.5 w-3.5 -translate-y-px" />
        {{ item.label }}
      </Link>
    </template>
  </nav>
</template>
