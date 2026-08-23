<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type RevisionSummary = {
  revisionNumber: number
  eventType: string
  eventLabel: string
  actor: string | null
  reason: string | null
  createdAt: string
  url: string
}

type Pagination = {
  page: number
  pages: number
  count: number
  from: number
  to: number
  prev: number | null
  next: number | null
  anchor: number
  pageSize: number
}

const props = defineProps<{
  title: string
  theme: { name: string; key: string; active: boolean; lockVersion: number }
  revisions: RevisionSummary[]
  pagination: Pagination
  backUrl: string
  copy: {
    back: string
    revision: string
    event: string
    actor: string
    reason: string
    created_at: string
    view: string
    empty: string
    range: string
  }
}>()

const rangeLabel = computed(() => props.copy.range
  .replace('__from__', String(props.pagination.from))
  .replace('__to__', String(props.pagination.to))
  .replace('__count__', String(props.pagination.count)))

function changePage(page: number) {
  router.get(
    window.location.pathname,
    { page, anchor: props.pagination.anchor },
    { preserveScroll: true, preserveState: true, replace: true },
  )
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :subtitle="`${theme.name} · ${theme.key}`" :show-back="false">
      <template #extra>
        <a-button @click="router.visit(backUrl)">{{ copy.back }}</a-button>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-table
        :data="revisions"
        row-key="revisionNumber"
        :pagination="false"
        :bordered="{ cell: true }"
        :scroll="{ minWidth: 920 }"
        stripe
      >
        <template #columns>
          <a-table-column :title="copy.revision" :width="110">
            <template #cell="{ record }">
              <a-tag color="arcoblue">#{{ record.revisionNumber }}</a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="copy.event" data-index="eventLabel" :width="150" />
          <a-table-column :title="copy.actor" :width="160">
            <template #cell="{ record }">{{ record.actor || '—' }}</template>
          </a-table-column>
          <a-table-column :title="copy.reason" :width="280">
            <template #cell="{ record }">
              <a-typography-text :ellipsis="{ rows: 2, showTooltip: true }">
                {{ record.reason || '—' }}
              </a-typography-text>
            </template>
          </a-table-column>
          <a-table-column :title="copy.created_at" data-index="createdAt" :width="210" />
          <a-table-column :width="110" fixed="right">
            <template #cell="{ record }">
              <a-button size="small" @click="router.visit(record.url)">{{ copy.view }}</a-button>
            </template>
          </a-table-column>
        </template>
        <template #empty><a-empty :description="copy.empty" /></template>
      </a-table>
    </a-card>

    <a-card v-if="pagination.count > 0" :bordered="true">
      <a-space direction="vertical" :size="12" fill>
        <a-typography-text type="secondary">
          {{ rangeLabel }}
        </a-typography-text>
        <a-pagination
          :current="pagination.page"
          :page-size="pagination.pageSize"
          :total="pagination.count"
          :hide-on-single-page="true"
          show-total
          @change="changePage"
        />
      </a-space>
    </a-card>
  </a-space>
</template>
