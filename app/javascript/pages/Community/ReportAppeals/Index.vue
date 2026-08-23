<script setup lang="ts">
import { ref } from 'vue'
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
  TypographyText,
  TypographyTitle,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'
import { createIdempotencyKey } from '@/lib/idempotency'

defineOptions({ layout: PortalLayout })

type AppealStatus = 'draft' | 'submitted' | 'under_review' | 'upheld' | 'overturned' | 'cancelled'

interface AppealSummary {
  public_id: string
  appellant_role: 'reporter' | 'affected_subject'
  status: AppealStatus
  public_outcome_code: 'upheld' | 'overturned' | 'cancelled' | null
  submitted_at: string | null
  state_changed_at: string
  detail_url: string
}

interface EligibleReport {
  public_id: string
  target_label: string
  state_changed_at: string
  create_url: string
  appellant_role: 'reporter' | 'affected_subject'
}

interface PaginationMeta {
  page: number
  pages: number
  count: number
}

const props = defineProps<{
  appeals: AppealSummary[]
  eligible_reports: EligibleReport[]
  pagination: PaginationMeta
}>()

const { t } = useI18n()
const creating = ref('')

function startAppeal(report: EligibleReport) {
  router.post(
    report.create_url,
    { appeal: { appellant_role: report.appellant_role, idempotency_key: createIdempotencyKey() } },
    {
      onStart: () => { creating.value = report.public_id },
      onFinish: () => { creating.value = '' },
    },
  )
}

function changePage(page: number) {
  if (page === props.pagination.page) return
  router.get(routes.forumReportAppeals, { page }, { preserveScroll: true })
}
</script>

<template>
  <Head :title="t('forum.reportAppeals.title')">
    <meta name="robots" content="noindex,nofollow">
  </Head>

  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reportAppeals.title')"
      :subtitle="t('forum.reportAppeals.subtitle')"
      :show-back="false"
    >
      <template #breadcrumb>
        <Breadcrumb>
          <BreadcrumbItem><Link :href="routes.forum">{{ t('breadcrumb.forum') }}</Link></BreadcrumbItem>
          <BreadcrumbItem>{{ t('forum.reportAppeals.navigation') }}</BreadcrumbItem>
        </Breadcrumb>
      </template>
      <Button type="outline" @click="router.visit(routes.forumReports)">
        {{ t('forum.reports.caseCenter') }}
      </Button>
    </PageHeader>

    <Card v-if="eligible_reports.length" :title="t('forum.reportAppeals.availableActions')" :bordered="true">
      <List :bordered="false" :split="true">
        <ListItem v-for="report in eligible_reports" :key="report.public_id">
          <Space direction="vertical" fill size="small">
            <TypographyText>{{ report.target_label }}</TypographyText>
            <TypographyText type="secondary">{{ report.state_changed_at }}</TypographyText>
            <Button
              type="primary"
              size="small"
              :loading="creating === report.public_id"
              :disabled="Boolean(creating)"
              @click="startAppeal(report)"
            >
              {{ report.appellant_role === 'reporter'
                ? t('forum.reportAppeals.requestReconsideration')
                : t('forum.reportAppeals.requestSubjectAppeal') }}
            </Button>
          </Space>
        </ListItem>
      </List>
    </Card>

    <Card :title="t('forum.reportAppeals.history')" :bordered="true">
      <List v-if="appeals.length" :bordered="false" :split="true">
        <ListItem v-for="appeal in appeals" :key="appeal.public_id">
          <Space direction="vertical" fill size="small">
            <Space wrap>
              <TypographyTitle :heading="6">
                {{ t('forum.reportAppeals.reference', { id: appeal.public_id }) }}
              </TypographyTitle>
              <Tag>{{ t(`forum.reportAppeals.roles.${appeal.appellant_role}`) }}</Tag>
              <Tag color="blue">{{ t(`forum.reportAppeals.status.${appeal.status}`) }}</Tag>
            </Space>
            <TypographyText type="secondary">{{ appeal.state_changed_at }}</TypographyText>
            <Button type="primary" size="small" @click="router.visit(appeal.detail_url)">
              {{ t('forum.reportAppeals.view') }}
            </Button>
          </Space>
        </ListItem>
      </List>
      <Empty v-else :description="t('forum.reportAppeals.empty')" />
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
