<script setup lang="ts">
import { computed } from 'vue'
import { usePage } from '@inertiajs/vue3'
import { Link } from '@inertiajs/vue3'

export interface BreadcrumbItem {
  label: string
  href?: string
  current?: boolean
}

defineProps<{
  items: BreadcrumbItem[]
}>()

const page = usePage()
const flash = computed(() => page.props.flash as { notice?: string; alert?: string } | undefined)
</script>

<template>
  <nav class="mb-4 flex items-center gap-2 text-sm text-muted-foreground" aria-label="Breadcrumb">
    <template v-for="(item, index) in items" :key="index">
      <span v-if="index > 0" aria-hidden="true">/</span>
      <span v-if="item.current || !item.href" class="text-foreground">{{ item.label }}</span>
      <Link v-else :href="item.href" class="hover:text-foreground transition-colors">
        {{ item.label }}
      </Link>
    </template>
  </nav>
</template>
