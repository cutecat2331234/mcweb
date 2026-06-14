<script setup lang="ts">
import { computed } from 'vue'
import { usePage } from '@inertiajs/vue3'

export interface PaginationMeta {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
  prev: number | null
  next: number | null
}

const props = defineProps<{
  pagination: PaginationMeta
  basePath: string
}>()

const pageUrl = (page: number) => {
  const url = new URL(props.basePath, window.location.origin)
  url.searchParams.set('page', String(page))
  return `${url.pathname}${url.search}`
}

const summary = computed(() => {
  if (!props.pagination.count) return 'No results'
  return `Showing ${props.pagination.from}–${props.pagination.to} of ${props.pagination.count}`
})
</script>

<template>
  <div v-if="pagination.pages > 1" class="mt-6 flex items-center justify-between text-sm">
    <p class="text-muted-foreground">{{ summary }}</p>
    <div class="flex items-center gap-2">
      <a
        v-if="pagination.prev"
        :href="pageUrl(pagination.prev)"
        class="rounded-md border px-3 py-1.5 hover:bg-muted transition-colors"
      >
        Previous
      </a>
      <span class="text-muted-foreground">Page {{ pagination.page }} / {{ pagination.pages }}</span>
      <a
        v-if="pagination.next"
        :href="pageUrl(pagination.next)"
        class="rounded-md border px-3 py-1.5 hover:bg-muted transition-colors"
      >
        Next
      </a>
    </div>
  </div>
</template>
