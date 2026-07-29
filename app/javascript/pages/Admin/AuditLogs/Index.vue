<script setup lang="ts">
import { computed, reactive } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  DatePicker,
  Empty,
  Form,
  FormItem,
  Grid,
  GridItem,
  Input,
  Option,
  PageHeader,
  Pagination,
  Select,
  Space,
  Table,
  TableColumn,
  Tag,
  TypographyText,
} from '@mcweb/ui'
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
  <section class="admin-audit-index">
    <PageHeader
      :title="t('admin.audit.title')"
      :subtitle="t('admin.audit.subtitle')"
      :show-back="false"
      class="mb-5 !px-0"
    >
      <template #extra>
        <Button
          v-if="canExport"
          type="primary"
          :aria-label="t('admin.audit.export')"
          @click="exportLogs"
        >
          {{ t('admin.audit.export') }}
        </Button>
      </template>
    </PageHeader>

    <Alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.audit.immutableNotice')"
      class="mb-4"
    />

    <Alert
      v-if="Object.keys(filterErrors).length"
      type="error"
      show-icon
      :closable="false"
      :title="t('admin.audit.invalidDate')"
      class="mb-4"
    />

    <Card :bordered="false" class="mb-4 audit-filter-card">
      <Form :model="form" layout="vertical" @submit.prevent="applyFilters">
        <Grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="16" :row-gap="4">
          <GridItem>
            <FormItem field="action" :label="t('admin.audit.action')">
              <Input
                v-model="form.action"
                allow-clear
                :placeholder="t('admin.audit.actionPlaceholder')"
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="actor" :label="t('admin.audit.actor')">
              <Input
                v-model="form.actor"
                allow-clear
                :placeholder="t('admin.audit.actorPlaceholder')"
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="resource_type" :label="t('admin.audit.resourceType')">
              <Select
                v-model="form.resource_type"
                allow-clear
                allow-search
                :placeholder="t('admin.audit.resourceTypePlaceholder')"
              >
                <Option v-for="resourceType in resourceTypes" :key="resourceType" :value="resourceType">
                  {{ resourceType }}
                </Option>
              </Select>
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="resource" :label="t('admin.audit.resource')">
              <Input
                v-model="form.resource"
                allow-clear
                :placeholder="t('admin.audit.resourcePlaceholder')"
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="request_id" :label="t('admin.audit.requestId')">
              <Input
                v-model="form.request_id"
                allow-clear
                :placeholder="t('admin.audit.requestIdPlaceholder')"
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="from" :label="t('admin.audit.from')">
              <DatePicker
                v-model="form.from"
                value-format="YYYY-MM-DD"
                format="YYYY-MM-DD"
                allow-clear
                class="w-full"
              />
            </FormItem>
          </GridItem>
          <GridItem>
            <FormItem field="to" :label="t('admin.audit.to')">
              <DatePicker
                v-model="form.to"
                value-format="YYYY-MM-DD"
                format="YYYY-MM-DD"
                allow-clear
                class="w-full"
              />
            </FormItem>
          </GridItem>
          <GridItem class="audit-filter-actions">
            <FormItem hide-label>
              <Space wrap>
                <Button type="primary" html-type="submit">
                  {{ t('admin.audit.applyFilters') }}
                </Button>
                <Button :disabled="activeFilterCount === 0" @click="clearFilters">
                  {{ t('admin.audit.clearFilters') }}
                </Button>
              </Space>
            </FormItem>
          </GridItem>
        </Grid>
      </Form>
    </Card>

    <Card :bordered="false" class="audit-table-card">
      <Empty v-if="rows.length === 0" :description="t('admin.audit.empty')" />
      <template v-else>
        <div class="audit-table-scroll">
          <Table
            :data="rows"
            :pagination="false"
            :bordered="{ wrapper: true }"
            :scroll="{ minWidth: 1040 }"
            row-key="id"
          >
            <template #columns>
              <TableColumn :title="t('admin.audit.action')" :width="230">
                <template #cell="{ record }">
                  <Link :href="record.showUrl" class="audit-primary-link">
                    {{ record.actionLabel }}
                  </Link>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.audit.actor')" :width="170">
                <template #cell="{ record }">
                  <TypographyText v-if="record.actor">{{ record.actor.username }}</TypographyText>
                  <TypographyText v-else type="secondary">{{ t('admin.audit.systemActor') }}</TypographyText>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.audit.resource')" :width="210">
                <template #cell="{ record }">
                  <Space direction="vertical" :size="0">
                    <TypographyText>{{ record.resource.typeLabel }}</TypographyText>
                    <TypographyText type="secondary">
                      {{ record.resource.publicId || record.resource.id || t('admin.audit.notAvailable') }}
                    </TypographyText>
                  </Space>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.audit.requestId')" :width="220">
                <template #cell="{ record }">
                  <Tag v-if="record.requestId" color="arcoblue" bordered>
                    {{ record.requestId }}
                  </Tag>
                  <TypographyText v-else type="secondary">{{ t('admin.audit.notAvailable') }}</TypographyText>
                </template>
              </TableColumn>
              <TableColumn :title="t('admin.audit.occurredAt')" :width="190">
                <template #cell="{ record }">
                  <time :datetime="record.occurredAtIso">{{ record.occurredAt }}</time>
                </template>
              </TableColumn>
            </template>
          </Table>
        </div>

        <div class="audit-pagination">
          <TypographyText type="secondary">
            {{ t('admin.audit.total', { count: pagination.total }) }}
          </TypographyText>
          <Pagination
            :current="pagination.page"
            :page-size="pagination.perPage"
            :total="pagination.total"
            :page-size-options="[25, 50, 100]"
            show-page-size
            show-total
            @change="changePage"
            @page-size-change="changePageSize"
          />
        </div>
      </template>
    </Card>
  </section>
</template>

<style scoped>
.audit-filter-actions {
  display: flex;
  align-items: end;
}

.audit-filter-actions :deep(.arco-form-item) {
  width: 100%;
}

.audit-table-scroll {
  overflow-x: auto;
}

.audit-primary-link {
  color: rgb(var(--primary-6));
  font-weight: 600;
  text-decoration: none;
}

.audit-primary-link:focus-visible {
  outline: 2px solid rgb(var(--primary-6));
  outline-offset: 3px;
  border-radius: 6px;
}

.audit-pagination {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-top: 16px;
}

@media (max-width: 575px) {
  .audit-pagination {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>
