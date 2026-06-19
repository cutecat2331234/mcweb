<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { ChevronRight, Home } from '@lucide/vue'
import { cn } from '@/lib/utils'

export interface BreadcrumbItem {
  label: string
  href?: string
  current?: boolean
}

const props = defineProps<{
  items: BreadcrumbItem[]
}>()

const { t } = useI18n()
const homeLabel = computed(() => t('breadcrumb.home'))

const legacyHomeLabels = ['Home', '首页']

function isHomeItem(item: BreadcrumbItem, index: number) {
  return index === 0 && (item.label === homeLabel.value || legacyHomeLabels.includes(item.label))
}
</script>

<template>
  <nav class="mb-6 flex flex-wrap items-center gap-1.5 text-sm text-muted-foreground" :aria-label="t('breadcrumb.label')">
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
        <Home v-if="isHomeItem(item, index)" class="mr-1 inline h-3.5 w-3.5 -translate-y-px" />
        {{ item.label }}
      </span>
      <Link
        v-else
        :href="item.href"
        class="truncate transition-colors hover:text-foreground"
      >
        <Home v-if="isHomeItem(item, index)" class="mr-1 inline h-3.5 w-3.5 -translate-y-px" />
        {{ item.label }}
      </Link>
    </template>
  </nav>
</template>
