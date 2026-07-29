<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { IconApps, IconSettings } from '@arco-design/web-vue/es/icon'
import { useI18n } from 'vue-i18n'

export interface ProColumn {
  key: string
  label: string
  link?: boolean
  width?: string | number
  minWidth?: string | number
  align?: 'left' | 'center' | 'right'
  fixed?: boolean | 'left' | 'right'
  sortable?: boolean
}

export interface ProPagination {
  page: number
  pages: number
  count: number
  from: number
  to: number
  prev: string | null
  next: string | null
}

export interface ProBulkAction {
  label: string
  action: string
  type?: 'primary' | 'success' | 'warning' | 'danger' | 'info'
}

type Density = 'large' | 'medium' | 'small'

const props = withDefaults(
  defineProps<{
    columns: ProColumn[]
    rows: Array<Record<string, unknown>>
    pagination?: ProPagination
    rowKey?: string
    selectable?: boolean
    bulkActionUrl?: string | null
    bulkActions?: ProBulkAction[]
    bulkMethod?: 'patch' | 'post'
    bulkParamKey?: string
    bulkActionKey?: string
    pageParam?: string
  }>(),
  {
    rowKey: 'publicId',
    selectable: false,
    bulkActionUrl: null,
    bulkActions: () => [],
    bulkMethod: 'patch',
    bulkParamKey: 'ids',
    bulkActionKey: 'action_type',
    pageParam: 'page',
  },
)

const emit = defineEmits<{
  (event: 'bulk', action: string, ids: Array<string | number>): void
}>()

const { t } = useI18n()
const density = ref<Density>('medium')
const densityOptions = computed<Array<{ label: string; value: Density }>>(() => [
  { label: t('common.tableDensity.comfortable'), value: 'large' },
  { label: t('common.tableDensity.default'), value: 'medium' },
  { label: t('common.tableDensity.compact'), value: 'small' },
])
const visibleKeys = ref(props.columns.map((column) => column.key))
const selectedIds = ref<Array<string | number>>([])
const visibleColumns = computed(() =>
  props.columns.filter((column) => visibleKeys.value.includes(column.key)),
)
const rowSelection = computed(() =>
  props.selectable
    ? {
        type: 'checkbox' as const,
        showCheckedAll: true,
        onlyCurrent: true,
        width: 46,
      }
    : undefined,
)
const pageSize = computed(() => {
  if (!props.pagination) return 20
  if (props.pagination.page > 1) {
    return Math.max(
      Math.round((props.pagination.from - 1) / (props.pagination.page - 1)),
      1,
    )
  }
  return Math.max(props.pagination.to - props.pagination.from + 1, 1)
})

function goToPage(page: number) {
  const url = new URL(window.location.href)
  url.searchParams.set(props.pageParam, String(page))
  router.get(url.pathname + url.search, {}, { preserveScroll: true, preserveState: true })
}

function runBulk(action: string) {
  if (!selectedIds.value.length) return
  emit('bulk', action, [...selectedIds.value])
  if (!props.bulkActionUrl) return

  const payload: Record<string, unknown> = {
    [props.bulkParamKey]: selectedIds.value,
    [props.bulkActionKey]: action,
    return_to: window.location.pathname + window.location.search,
  }
  router[props.bulkMethod](props.bulkActionUrl, payload, {
    preserveScroll: true,
    onSuccess: () => {
      selectedIds.value = []
    },
  })
}

function actionStatus(type?: ProBulkAction['type']) {
  if (type === 'success' || type === 'warning' || type === 'danger') return type
  return undefined
}

function columnSorter(column: ProColumn) {
  if (!column.sortable) return undefined
  return {
    sortDirections: ['ascend', 'descend'] as Array<'ascend' | 'descend'>,
    sorter: (left: Record<string, unknown>, right: Record<string, unknown>) =>
      String(left[column.key] ?? '').localeCompare(String(right[column.key] ?? '')),
  }
}
</script>

<template>
  <div>
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <a-space wrap>
        <slot name="toolbar-left" />
      </a-space>
      <a-space wrap>
        <a-button
          v-for="action in selectable && selectedIds.length ? bulkActions : []"
          :key="action.action"
          :type="action.type === 'primary' ? 'primary' : 'secondary'"
          :status="actionStatus(action.type)"
          @click="runBulk(action.action)"
        >
          {{ action.label }} ({{ selectedIds.length }})
        </a-button>

        <slot name="toolbar-right" />

        <a-dropdown trigger="click" @select="density = $event as Density">
          <a-tooltip :content="t('common.tableDensity.label')">
            <a-button shape="circle" :aria-label="t('common.tableDensity.label')">
              <template #icon><icon-apps /></template>
            </a-button>
          </a-tooltip>
          <template #content>
            <a-doption
              v-for="option in densityOptions"
              :key="option.value"
              :value="option.value"
              :disabled="density === option.value"
            >
              {{ option.label }}
            </a-doption>
          </template>
        </a-dropdown>

        <a-popover trigger="click" position="br">
          <a-tooltip :content="t('common.tableColumns')">
            <a-button shape="circle" :aria-label="t('common.tableColumns')">
              <template #icon><icon-settings /></template>
            </a-button>
          </a-tooltip>
          <template #content>
            <a-checkbox-group v-model="visibleKeys">
              <a-space direction="vertical">
                <a-checkbox
                  v-for="column in columns"
                  :key="column.key"
                  :value="column.key"
                >
                  {{ column.label }}
                </a-checkbox>
              </a-space>
            </a-checkbox-group>
          </template>
        </a-popover>
      </a-space>
    </div>

    <a-table
      v-model:selected-keys="selectedIds"
      :data="rows"
      :row-key="rowKey"
      :row-selection="rowSelection"
      :pagination="false"
      :size="density"
      :bordered="{ cell: true }"
      :scroll="{ x: 720 }"
      stripe
    >
      <template #columns>
        <a-table-column
          v-for="column in visibleColumns"
          :key="column.key"
          :title="column.label"
          :data-index="column.key"
          :width="column.width"
          :min-width="column.minWidth || 120"
          :align="column.align || 'left'"
          :fixed="column.fixed"
          :sortable="columnSorter(column)"
          ellipsis
          tooltip
        >
          <template #cell="{ record }">
            <slot
              :name="`cell-${column.key}`"
              :row="record"
              :value="record[column.key]"
            >
              <Link
                v-if="column.link && record.url"
                :href="String(record.url)"
                class="arco-link font-medium no-underline"
              >
                {{ record[column.key] }}
              </Link>
              <span v-else>{{ record[column.key] }}</span>
            </slot>
          </template>
        </a-table-column>
      </template>
      <template #empty>
        <slot name="empty"><a-empty /></slot>
      </template>
    </a-table>

    <div
      v-if="pagination"
      class="mt-4 flex flex-wrap items-center justify-between gap-3"
    >
      <a-typography-text type="secondary">
        {{
          t('common.tableRange', {
            count: pagination.count,
            from: pagination.from,
            to: pagination.to,
          })
        }}
      </a-typography-text>
      <a-pagination
        v-if="pagination.pages > 1"
        :current="pagination.page"
        :total="pagination.count"
        :page-size="pageSize"
        :show-total="true"
        @change="goToPage"
      />
    </div>
  </div>
</template>
