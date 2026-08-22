<script setup lang="ts">
import { Head, Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Card,
  Empty,
  List,
  ListItem,
  PageHeader,
  Pagination,
  Space,
  Tag,
  TypographyParagraph,
  TypographyText,
  TypographyTitle,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

interface ReportSummary {
  id: number
  target_label: string
  reason_label: string
  reason_detail: string | null
  status: 'pending' | 'withdrawn' | 'reviewed' | 'dismissed' | 'actioned'
  public_outcome_code: 'withdrawn' | 'review_complete' | 'not_upheld' | 'action_taken' | null
  submitted_at: string
  state_changed_at: string
  detail_url: string
}

interface PaginationMeta {
  page: number
  pages: number
  count: number
}

const props = defineProps<{
  reports: ReportSummary[]
  pagination: PaginationMeta
}>()

const statusLabels = {
  pending: () => t('forum.reports.status.pending'),
  withdrawn: () => t('forum.reports.status.withdrawn'),
  reviewed: () => t('forum.reports.status.reviewed'),
  dismissed: () => t('forum.reports.status.dismissed'),
  actioned: () => t('forum.reports.status.actioned'),
}

const outcomeLabels = {
  withdrawn: () => t('forum.reports.outcome.withdrawn'),
  review_complete: () => t('forum.reports.outcome.reviewComplete'),
  not_upheld: () => t('forum.reports.outcome.notUpheld'),
  action_taken: () => t('forum.reports.outcome.actionTaken'),
}

function statusLabel(status: ReportSummary['status']) {
  return statusLabels[status]()
}

function outcomeLabel(outcome: ReportSummary['public_outcome_code']) {
  return outcome ? outcomeLabels[outcome]() : t('forum.reports.outcome.pending')
}

function statusColor(status: ReportSummary['status']) {
  if (status === 'pending') return 'orange'
  if (status === 'actioned') return 'green'
  if (status === 'dismissed') return 'gray'
  return 'blue'
}

function changePage(page: number) {
  if (page === props.pagination.page) return
  router.get(routes.forumReports, { page }, { preserveScroll: true })
}
</script>

<template>
  <Head :title="t('forum.reports.caseCenter')">
    <meta name="robots" content="noindex,nofollow">
  </Head>

  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reports.caseCenter')"
      :subtitle="t('forum.reports.caseCenterSubtitle')"
      :show-back="false"
    >
      <template #breadcrumb>
        <Breadcrumb>
          <BreadcrumbItem><Link :href="routes.forum">{{ t('breadcrumb.forum') }}</Link></BreadcrumbItem>
          <BreadcrumbItem>{{ t('forum.reports.caseCenter') }}</BreadcrumbItem>
        </Breadcrumb>
      </template>
    </PageHeader>

    <Card :bordered="true">
      <List v-if="reports.length" :bordered="false" :split="true">
        <ListItem v-for="report in reports" :key="report.id">
          <Space direction="vertical" fill size="small">
            <Space wrap>
              <TypographyTitle :heading="6">
                {{ t('forum.reports.caseReference', { id: report.id }) }}
              </TypographyTitle>
              <Tag :color="statusColor(report.status)">{{ statusLabel(report.status) }}</Tag>
            </Space>
            <TypographyText>{{ report.target_label }}</TypographyText>
            <TypographyParagraph v-if="report.reason_detail" type="secondary">
              {{ report.reason_label }} · {{ report.reason_detail }}
            </TypographyParagraph>
            <TypographyText v-else type="secondary">{{ report.reason_label }}</TypographyText>
            <TypographyText type="secondary">
              {{ t('forum.reports.submittedAt', { at: report.submitted_at }) }}
            </TypographyText>
            <TypographyText type="secondary">
              {{ t('forum.reports.outcomeLabel', { outcome: outcomeLabel(report.public_outcome_code) }) }}
            </TypographyText>
            <Space>
              <Button type="primary" size="small" @click="router.visit(report.detail_url)">
                {{ t('forum.reports.viewCase') }}
              </Button>
            </Space>
          </Space>
        </ListItem>
      </List>
      <Empty v-else :description="t('forum.reports.empty')" />
    </Card>

    <Pagination
      v-if="pagination.pages > 1"
      :total="pagination.count"
      :current="pagination.page"
      :page-size="25"
      :hide-on-single-page="true"
      :show-total="true"
      @change="changePage"
    />
  </Space>
</template>
