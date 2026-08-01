<script setup lang="ts">
import { computed, reactive } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { IconDownload, IconFilter, IconRefresh } from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type AuditRow = {
  id: number
  actionLabel: string
  actionCode: string
  actor: { username: string; publicId: string } | null
  resource: {
    type: string | null
    typeLabel: string
    id: number | null
    publicId: string | null
  }
  requestId: string | null
  reason: string | null
  occurredAt: string
  occurredAtIso: string
  showUrl: string
}

type Filters = {
  action?: string | null
  actor?: string | null
  resource_type?: string | null
  resource?: string | null
  request_id?: string | null
  from?: string | null
  to?: string | null
}

const props = defineProps<{
  rows: AuditRow[]
  filters: Filters
  filterErrors: Partial<Record<'from' | 'to', string>>
  pagination: {
    page: number
    perPage: number
    total: number
    totalPages: number
  }
  canExport: boolean
  exportUrl: string
  resourceTypes: string[]
}>()

const { t } = useI18n()
const form = reactive({
  action: props.filters.action || '',
  actor: props.filters.actor || '',
  resource_type: props.filters.resource_type || '',
  resource: props.filters.resource || '',
  request_id: props.filters.request_id || '',
  from: props.filters.from || '',
  to: props.filters.to || '',
})

const activeFilterCount = computed(() => Object.values(form).filter(Boolean).length)

function query(page = 1, perPage = props.pagination.perPage) {
  const { action, ...filters } = form
  return Object.fromEntries(
    Object.entries({
      ...filters,
      event_action: action,
      page,
      per_page: perPage,
    }).filter(([, value]) => value !== ''),
  )
}

function applyFilters() {
  router.get(window.location.pathname, query(), {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function clearFilters() {
  Object.assign(form, {
    action: '',
    actor: '',
    resource_type: '',
    resource: '',
    request_id: '',
    from: '',
    to: '',
  })
  applyFilters()
}

function changePage(page: number) {
  router.get(window.location.pathname, query(page), {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function changePageSize(perPage: number) {
  router.get(window.location.pathname, query(1, perPage), {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function visitDetail(url: string) {
  router.visit(url, {
    preserveScroll: true,
    preserveState: true,
  })
}

function exportLogs() {
  const url = new URL(props.exportUrl, window.location.origin)
  Object.entries(query()).forEach(([key, value]) => {
    if (!['page', 'per_page'].includes(key)) url.searchParams.set(key, String(value))
  })

  const anchor = document.createElement('a')
  anchor.href = url.toString()
  anchor.download = ''
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="t('admin.audit.title')" :subtitle="t('admin.audit.subtitle')" :show-back="false">
      <template #extra>
        <a-button
          v-if="canExport"
          type="primary"
          shape="round"
          :aria-label="t('admin.audit.export')"
          @click="exportLogs"
        >
          <template #icon><icon-download /></template>
          {{ t('admin.audit.export') }}
        </a-button>
      </template>
    </a-page-header>

    <a-alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.audit.immutableNotice')"
    />

    <a-alert
      v-if="Object.keys(filterErrors).length"
      type="error"
      show-icon
      :closable="false"
      :title="t('admin.audit.invalidDate')"
    />

    <a-card :bordered="false">
      <a-form :model="form" layout="vertical" @submit="applyFilters">
        <a-grid :cols="{ xs: 1, md: 2, xl: 4 }" :col-gap="16" :row-gap="8">
          <a-grid-item>
            <a-form-item field="action" :label="t('admin.audit.action')">
              <a-input
                v-model="form.action"
                allow-clear
                :placeholder="t('admin.audit.actionPlaceholder')"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="actor" :label="t('admin.audit.actor')">
              <a-input
                v-model="form.actor"
                allow-clear
                :placeholder="t('admin.audit.actorPlaceholder')"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="resource_type" :label="t('admin.audit.resourceType')">
              <a-select
                v-model="form.resource_type"
                allow-clear
                allow-search
                :placeholder="t('admin.audit.resourceTypePlaceholder')"
              >
                <a-option v-for="resourceType in resourceTypes" :key="resourceType" :value="resourceType">
                  {{ resourceType }}
                </a-option>
              </a-select>
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="resource" :label="t('admin.audit.resource')">
              <a-input
                v-model="form.resource"
                allow-clear
                :placeholder="t('admin.audit.resourcePlaceholder')"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="request_id" :label="t('admin.audit.requestId')">
              <a-input
                v-model="form.request_id"
                allow-clear
                :placeholder="t('admin.audit.requestIdPlaceholder')"
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="from" :label="t('admin.audit.from')">
              <a-date-picker
                v-model="form.from"
                value-format="YYYY-MM-DD"
                format="YYYY-MM-DD"
                allow-clear
                long
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item field="to" :label="t('admin.audit.to')">
              <a-date-picker
                v-model="form.to"
                value-format="YYYY-MM-DD"
                format="YYYY-MM-DD"
                allow-clear
                long
              />
            </a-form-item>
          </a-grid-item>
          <a-grid-item>
            <a-form-item :label="t('admin.audit.applyFilters')">
              <a-space wrap>
                <a-button type="primary" shape="round" html-type="submit">
                  <template #icon><icon-filter /></template>
                  {{ t('admin.audit.applyFilters') }}
                </a-button>
                <a-button shape="round" :disabled="activeFilterCount === 0" @click="clearFilters">
                  <template #icon><icon-refresh /></template>
                  {{ t('admin.audit.clearFilters') }}
                </a-button>
              </a-space>
            </a-form-item>
          </a-grid-item>
        </a-grid>
      </a-form>
    </a-card>

    <a-card :bordered="false">
      <a-empty v-if="rows.length === 0" :description="t('admin.audit.empty')" />
      <template v-else>
        <a-table
          :data="rows"
          :pagination="false"
          :bordered="{ wrapper: true }"
          :scroll="{ minWidth: 1040 }"
          row-key="id"
          stripe
        >
          <template #columns>
            <a-table-column :title="t('admin.audit.action')" :width="230">
              <template #cell="{ record }">
                <a-link :href="record.showUrl" @click.prevent="visitDetail(record.showUrl)">
                  {{ record.actionLabel }}
                </a-link>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.audit.actor')" :width="170">
              <template #cell="{ record }">
                <a-typography-text v-if="record.actor">{{ record.actor.username }}</a-typography-text>
                <a-typography-text v-else type="secondary">{{ t('admin.audit.systemActor') }}</a-typography-text>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.audit.resource')" :width="210">
              <template #cell="{ record }">
                <a-space direction="vertical" :size="0">
                  <a-typography-text>{{ record.resource.typeLabel }}</a-typography-text>
                  <a-typography-text type="secondary">
                    {{ record.resource.publicId || record.resource.id || t('admin.audit.notAvailable') }}
                  </a-typography-text>
                </a-space>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.audit.requestId')" :width="220">
              <template #cell="{ record }">
                <a-tag v-if="record.requestId" color="arcoblue" bordered>
                  {{ record.requestId }}
                </a-tag>
                <a-typography-text v-else type="secondary">{{ t('admin.audit.notAvailable') }}</a-typography-text>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.audit.occurredAt')" :width="190">
              <template #cell="{ record }">
                <time :datetime="record.occurredAtIso">{{ record.occurredAt }}</time>
              </template>
            </a-table-column>
          </template>
        </a-table>

        <a-space direction="vertical" :size="12" fill>
          <a-typography-text type="secondary">
            {{ t('admin.audit.total', { count: pagination.total }) }}
          </a-typography-text>
          <a-pagination
            :current="pagination.page"
            :page-size="pagination.perPage"
            :total="pagination.total"
            :page-size-options="[25, 50, 100]"
            show-page-size
            show-total
            @change="changePage"
            @page-size-change="changePageSize"
          />
        </a-space>
      </template>
    </a-card>
  </a-space>
</template>
