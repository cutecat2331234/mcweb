<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

export interface PaginationMeta {
  page: number
  pages: number
  count: number
  from: number | null
  to: number | null
  prev: number | null
  next: number | null
}

const props = withDefaults(defineProps<{
  pagination: PaginationMeta
  basePath: string
  pageParam?: string
  query?: Record<string, string | number | boolean | null | undefined>
}>(), {
  pageParam: 'page',
  query: () => ({}),
})

const pageUrl = (page: number) => {
  const url = new URL(window.location.href)
  const baseUrl = new URL(props.basePath, window.location.origin)
  url.pathname = baseUrl.pathname
  baseUrl.searchParams.forEach((value, key) => url.searchParams.set(key, value))
  Object.entries(props.query).forEach(([key, value]) => {
    if (value === null || value === undefined || value === '') url.searchParams.delete(key)
    else url.searchParams.set(key, String(value))
  })
  url.searchParams.set(props.pageParam, String(page))
  return `${url.pathname}${url.search}`
}

const summary = computed(() => {
  if (!props.pagination.count) return t('common.pagination.noResults')
  return t('common.pagination.summary', {
    from: props.pagination.from,
    to: props.pagination.to,
    count: props.pagination.count,
  })
})

function visitPage(page: number) {
  if (page === props.pagination.page) return
  router.visit(pageUrl(page))
}
</script>

<template>
  <div v-if="pagination.pages > 1" class="mt-6 flex items-center justify-between text-sm">
    <p class="text-muted-foreground">{{ summary }}</p>
    <div class="flex items-center gap-2">
      <a
        v-if="pagination.prev"
        :href="pageUrl(pagination.prev)"
        @click.prevent="visitPage(pagination.prev)"
        class="rounded-md border px-3 py-1.5 hover:bg-muted transition-colors"
      >
        {{ t('common.pagination.previous') }}
      </a>
      <span class="text-muted-foreground">
        {{ t('common.pagination.page', { page: pagination.page, pages: pagination.pages }) }}
      </span>
      <a
        v-if="pagination.next"
        :href="pageUrl(pagination.next)"
        @click.prevent="visitPage(pagination.next)"
        class="rounded-md border px-3 py-1.5 hover:bg-muted transition-colors"
      >
        {{ t('common.pagination.next') }}
      </a>
    </div>
  </div>
</template>
