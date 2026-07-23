<script setup lang="ts">
/**
 * ProTable — a thin Element Plus wrapper that keeps the project's existing
 * server-driven list semantics (Rails offset pagination + URL-param filters +
 * Inertia bulk actions) while adding the affordances the hand-rolled shadcn
 * table in pages/Admin/Generic/Index.vue lacks: column show/hide, density
 * switching, per-column client sort of the visible page, and colored cells via
 * scoped slots.
 *
 * It deliberately does NOT introduce a client-side data source: `rows` are the
 * current server page, `pagination` describes the server's offset window, and
 * page changes navigate (`router.get ?page=`) rather than slicing locally — so
 * Rails stays the single source of truth.
 *
 * Per-column colored badges (order status, payment status, ...) are provided by
 * the parent via a `cell-<key>` scoped slot, keeping ProTable domain-agnostic.
 */
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { Grid, Setting } from '@element-plus/icons-vue'

export interface ProColumn {
  key: string
  label: string
  /** Render the value as an Inertia <Link> to `row.url` when present. */
  link?: boolean
  width?: string | number
  minWidth?: string | number
  align?: 'left' | 'center' | 'right'
  fixed?: boolean | 'left' | 'right'
  /** Enable client-side sort of the CURRENT server page (does not re-query). */
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

type Density = 'large' | 'default' | 'small'

const props = withDefaults(
  defineProps<{
    columns: ProColumn[]
    rows: Array<Record<string, unknown>>
    pagination?: ProPagination
    /** Field used as el-table row-key + selection identity (default publicId). */
    rowKey?: string
    selectable?: boolean
    /** Inertia endpoint the bulk action posts to (null = emit-only demo). */
    bulkActionUrl?: string | null
    bulkActions?: ProBulkAction[]
    bulkMethod?: 'patch' | 'post'
    /** Payload key holding the selected ids (e.g. 'order_ids'). */
    bulkParamKey?: string
    /** Payload key holding the action name (e.g. 'action_type'). */
    bulkActionKey?: string
    /** Query param used for server-side paging. */
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
  (e: 'bulk', action: string, ids: Array<string | number>): void
}>()

/* ---- density -------------------------------------------------------------- */
const density = ref<Density>('default')
const densityOptions: Array<{ label: string; value: Density }> = [
  { label: '宽松', value: 'large' },
  { label: '默认', value: 'default' },
  { label: '紧凑', value: 'small' },
]
function setDensity(value: Density) {
  density.value = value
}

/* ---- column visibility ---------------------------------------------------- */
const visibleKeys = ref<string[]>(props.columns.map((c) => c.key))
const visibleColumns = computed(() =>
  props.columns.filter((c) => visibleKeys.value.includes(c.key)),
)

/* ---- selection ------------------------------------------------------------ */
const selectedIds = ref<Array<string | number>>([])
function onSelectionChange(rows: Array<Record<string, unknown>>) {
  selectedIds.value = rows
    .map((r) => r[props.rowKey] as string | number)
    .filter((v) => v != null)
}

/* ---- server-side pagination ---------------------------------------------- */
function goToPage(page: number) {
  const url = new URL(window.location.href)
  url.searchParams.set(props.pageParam, String(page))
  router.get(url.pathname + url.search, {}, { preserveScroll: true, preserveState: false })
}

/* ---- bulk actions (Inertia round-trip, mirrors Generic/Index semantics) --- */
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
</script>

<template>
  <div class="pro-table">
    <!-- Toolbar -->
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <div class="flex flex-wrap items-center gap-3">
        <slot name="toolbar-left" />
      </div>
      <div class="flex items-center gap-3">
        <template v-if="selectable && bulkActions.length && selectedIds.length">
          <el-button
            v-for="a in bulkActions"
            :key="a.action"
            :type="a.type || 'default'"
            @click="runBulk(a.action)"
          >
            {{ a.label }}（{{ selectedIds.length }}）
          </el-button>
        </template>

        <slot name="toolbar-right" />

        <!-- density -->
        <el-dropdown trigger="click" @command="setDensity">
          <el-button :icon="Grid" circle title="密度" />
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item
                v-for="d in densityOptions"
                :key="d.value"
                :command="d.value"
                :disabled="density === d.value"
              >
                {{ d.label }}
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>

        <!-- column settings -->
        <el-popover trigger="click" :width="180" placement="bottom-end">
          <template #reference>
            <el-button :icon="Setting" circle title="列设置" />
          </template>
          <p class="mb-2 text-xs text-[var(--el-text-color-secondary)]">列设置</p>
          <el-checkbox-group v-model="visibleKeys" class="flex flex-col gap-1">
            <el-checkbox v-for="c in columns" :key="c.key" :value="c.key">
              {{ c.label }}
            </el-checkbox>
          </el-checkbox-group>
        </el-popover>
      </div>
    </div>

    <!-- Table (data = current server page only) -->
    <el-table
      :data="rows"
      :size="density"
      :row-key="rowKey"
      border
      stripe
      style="width: 100%"
      @selection-change="onSelectionChange"
    >
      <el-table-column v-if="selectable" type="selection" width="46" />
      <el-table-column
        v-for="c in visibleColumns"
        :key="c.key"
        :prop="c.key"
        :label="c.label"
        :width="c.width"
        :min-width="c.minWidth || 120"
        :align="c.align || 'left'"
        :fixed="c.fixed"
        :sortable="c.sortable || false"
        show-overflow-tooltip
      >
        <template #default="{ row }">
          <slot :name="`cell-${c.key}`" :row="row" :value="row[c.key]">
            <Link
              v-if="c.link && row.url"
              :href="row.url as string"
              class="font-medium text-[var(--el-color-primary)] no-underline hover:underline"
            >
              {{ row[c.key] }}
            </Link>
            <span v-else>{{ row[c.key] }}</span>
          </slot>
        </template>
      </el-table-column>

      <template #empty>
        <slot name="empty">暂无数据</slot>
      </template>
    </el-table>

    <!-- Pagination summary + server-side pager -->
    <div class="mt-4 flex flex-wrap items-center justify-between gap-3">
      <span v-if="pagination" class="text-xs text-[var(--el-text-color-secondary)]">
        共 {{ pagination.count }} 条 · 显示第 {{ pagination.from }}–{{ pagination.to }} 条
      </span>
      <el-pagination
        v-if="pagination && pagination.pages > 1"
        background
        layout="prev, pager, next"
        :page-count="pagination.pages"
        :current-page="pagination.page"
        @current-change="goToPage"
      />
    </div>
  </div>
</template>
