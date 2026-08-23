<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Button,
  Card,
  Empty,
  PageHeader,
  Pagination,
  Select,
  Option,
  Space,
  Table,
  TableColumn,
  Tag,
} from '@mcweb/ui'
import type { ReportAppealPagination, ReportAppealReviewRow } from '@/types/communityReportAppeals'

const props = defineProps<{
  appeals: ReportAppealReviewRow[]
  pagination: ReportAppealPagination
  filters: { status?: string | null }
  paginationUrl: string
}>()

const { t } = useI18n()

function changeStatus(status: string | number | undefined) {
  const normalized = status?.toString() || ''
  router.get(props.paginationUrl, normalized ? { status: normalized } : {}, { preserveState: true, replace: true })
}

function changePage(page: number) {
  router.get(
    props.paginationUrl,
    { page, status: props.filters.status || undefined },
    { preserveState: true, preserveScroll: true },
  )
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reportAppeals.review.title')"
      :subtitle="t('forum.reportAppeals.review.subtitle')"
      :show-back="false"
    />
    <Card :bordered="true">
      <Space direction="vertical" fill size="large">
        <Select
          :model-value="filters.status || ''"
          allow-clear
          :placeholder="t('forum.reportAppeals.review.filterStatus')"
          @change="changeStatus"
        >
          <Option value="submitted">{{ t('forum.reportAppeals.status.submitted') }}</Option>
          <Option value="under_review">{{ t('forum.reportAppeals.status.under_review') }}</Option>
          <Option value="upheld">{{ t('forum.reportAppeals.status.upheld') }}</Option>
          <Option value="overturned">{{ t('forum.reportAppeals.status.overturned') }}</Option>
          <Option value="cancelled">{{ t('forum.reportAppeals.status.cancelled') }}</Option>
        </Select>
        <Table
          v-if="appeals.length"
          :data="appeals"
          :pagination="false"
          row-key="public_id"
          :scroll="{ minWidth: 980 }"
        >
          <TableColumn :title="t('forum.reportAppeals.review.reference')" data-index="public_id" :width="210" />
          <TableColumn :title="t('forum.reportAppeals.review.appellant')" data-index="appellant" :width="160" />
          <TableColumn :title="t('forum.reportAppeals.role')" :width="150">
            <template #cell="{ record }">
              {{ t(`forum.reportAppeals.roles.${record.appellant_role}`) }}
            </template>
          </TableColumn>
          <TableColumn :title="t('forum.reports.target')" data-index="report_target" />
          <TableColumn :title="t('forum.reportAppeals.review.status')" :width="140">
            <template #cell="{ record }">
              <Tag color="blue">{{ t(`forum.reportAppeals.status.${record.status}`) }}</Tag>
            </template>
          </TableColumn>
          <TableColumn :title="t('forum.reportAppeals.review.actions')" :width="120" fixed="right">
            <template #cell="{ record }">
              <Button type="text" @click="router.visit(record.detail_url)">
                {{ t('forum.reportAppeals.review.open') }}
              </Button>
            </template>
          </TableColumn>
        </Table>
        <Empty v-else :description="t('forum.reportAppeals.review.empty')" />
        <Pagination
          v-if="pagination.pages > 1"
          :total="pagination.count"
          :current="pagination.page"
          :page-size="25"
          @change="changePage"
        />
      </Space>
    </Card>
  </Space>
</template>
