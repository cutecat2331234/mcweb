<script setup lang="ts">
import { computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Badge,
  Card,
  Empty,
  Grid,
  GridItem,
  PageHeader,
  Pagination,
  Select,
  Space,
  Statistic,
  Table,
  TableColumn,
  Tag,
  TypographyText,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

type FulfillmentRow = {
  id: number
  delivery_id: string
  status: string
  status_label: string
  order_number: string
  product_name: string
  attempts_count: number
  max_attempts: number
  next_attempt_at?: string | null
  error_label?: string | null
  url: string
}

const props = defineProps<{
  summary: {
    total: number
    pending: number
    failed: number
    exhausted: number
  }
  filters: {
    status?: string | null
  }
  status_options: Array<{ value: string; label: string }>
  rows: FulfillmentRow[]
  pagination: {
    page: number
    pages: number
    count: number
    limit: number
  }
}>()

const { t, locale } = useI18n()
const selectedStatus = computed({
  get: () => props.filters.status ?? '',
  set: (value: string) => {
    router.get(
      adminRoutes.storeFulfillments,
      value ? { status: value } : {},
      { preserveState: true, preserveScroll: true, replace: true },
    )
  },
})

function statusColor(status: string) {
  if (status === 'fulfilled') return 'green'
  if (status === 'failed') return 'red'
  if (status === 'cancelled') return 'gray'
  if (status === 'processing') return 'arcoblue'
  return 'orange'
}

function formatDate(value?: string | null) {
  if (!value) return t('admin.fulfillments.notScheduled')
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function changePage(page: number) {
  router.get(
    adminRoutes.storeFulfillments,
    {
      page,
      ...(props.filters.status ? { status: props.filters.status } : {}),
    },
    { preserveState: true, preserveScroll: true, replace: true },
  )
}
</script>

<template>
  <PageHeader
    :title="t('admin.fulfillments.indexTitle')"
    :subtitle="t('admin.fulfillments.indexSubtitle')"
  />

  <Space direction="vertical" size="large" fill>
    <Alert
      v-if="summary.exhausted > 0"
      type="error"
      show-icon
      :title="t('admin.fulfillments.exhaustedAlertTitle', { count: summary.exhausted })"
    >
      {{ t('admin.fulfillments.exhaustedAlertDescription') }}
    </Alert>

    <Grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="16" :row-gap="16">
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.fulfillments.metrics.total')" :value="summary.total" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.fulfillments.metrics.pending')" :value="summary.pending" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.fulfillments.metrics.failed')" :value="summary.failed" />
        </Card>
      </GridItem>
      <GridItem>
        <Card :bordered="false">
          <Statistic :title="t('admin.fulfillments.metrics.exhausted')" :value="summary.exhausted" />
        </Card>
      </GridItem>
    </Grid>

    <Card :title="t('admin.fulfillments.queueTitle')" :bordered="false">
      <template #extra>
        <Select
          v-model="selectedStatus"
          :placeholder="t('admin.fulfillments.filterStatus')"
          allow-clear
          :style="{ width: '220px', maxWidth: '50vw' }"
        >
          <a-option
            v-for="option in status_options"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </a-option>
        </Select>
      </template>

      <Empty v-if="rows.length === 0" :description="t('admin.fulfillments.empty')" />
      <Table
        v-else
        :data="rows"
        :pagination="false"
        row-key="id"
        :scroll="{ x: 1040 }"
      >
        <TableColumn :title="t('admin.fulfillments.columns.delivery')" :width="230">
          <template #cell="{ record }">
            <Link :href="record.url" class="arco-link no-underline">
              {{ record.delivery_id }}
            </Link>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.common.status')" :width="140">
          <template #cell="{ record }">
            <Tag :color="statusColor(record.status)">{{ record.status_label }}</Tag>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.common.order')" data-index="order_number" :width="170" />
        <TableColumn :title="t('admin.common.product')" data-index="product_name" :width="220" />
        <TableColumn :title="t('admin.fulfillments.attempts')" :width="150">
          <template #cell="{ record }">
            <Badge
              :count="`${record.attempts_count} / ${record.max_attempts}`"
              :dot="false"
              :max-count="999"
            />
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.fulfillments.nextAttempt')" :width="220">
          <template #cell="{ record }">
            <TypographyText :type="record.next_attempt_at ? 'warning' : 'secondary'">
              {{ formatDate(record.next_attempt_at) }}
            </TypographyText>
          </template>
        </TableColumn>
        <TableColumn :title="t('admin.fulfillments.lastResult')" :width="260">
          <template #cell="{ record }">
            <TypographyText v-if="record.error_label" type="danger">
              {{ record.error_label }}
            </TypographyText>
            <TypographyText v-else type="secondary">
              {{ t('admin.fulfillments.noError') }}
            </TypographyText>
          </template>
        </TableColumn>
      </Table>

      <div v-if="pagination.pages > 1" class="mt-5 flex justify-end">
        <Pagination
          :current="pagination.page"
          :total="pagination.count"
          :page-size="pagination.limit"
          show-total
          @change="changePage"
        />
      </div>
    </Card>
  </Space>
</template>
