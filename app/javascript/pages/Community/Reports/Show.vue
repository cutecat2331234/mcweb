<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { Head, Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Breadcrumb,
  BreadcrumbItem,
  Button,
  Card,
  Descriptions,
  DescriptionsItem,
  Empty,
  Form,
  FormItem,
  List,
  ListItem,
  PageHeader,
  Space,
  Tag,
  Textarea,
  TypographyParagraph,
  TypographyText,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/arcoConfirm'
import { createIdempotencyKey } from '@/lib/idempotency'
import { csrfHeaders } from '@/lib/csrf'
import SecureEvidenceUpload from '@/components/community/SecureEvidenceUpload.vue'
import type { SecureEvidenceAttachment } from '@/types/communityReportAppeals'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

interface ReporterCase {
  id: string
  public_id: string
  target_label: string
  reason_label: string
  reason_detail: string | null
  status: 'pending' | 'withdrawn' | 'reviewed' | 'dismissed' | 'actioned'
  public_outcome_code: 'withdrawn' | 'review_complete' | 'not_upheld' | 'action_taken' | null
  submitted_at: string
  state_changed_at: string
  lock_version: number
  index_url: string
  supplement_url: string
  withdraw_url: string
  can_supplement: boolean
  can_withdraw: boolean
  evidence_url: string
  evidence_subject: {
    key: 'community.report'
    public_id: string
  }
  evidence_attachments: SecureEvidenceAttachment[]
  appeal_roles: Array<'reporter'>
  appeal_draft_url: string
  appeals_url: string
  supplements: Array<{
    id: number
    body: string
    created_at: string
  }>
}

const props = defineProps<{
  report: ReporterCase
  evidence_upload_url: string
  form_errors?: Record<string, string> | null
}>()

const supplementForm = useForm({
  supplement: {
    body: '',
    idempotency_key: createIdempotencyKey(),
    lock_version: props.report.lock_version,
  },
})
const withdrawalKey = ref(createIdempotencyKey())
const withdrawing = ref(false)
const submittedSupplement = ref<{ body: string; key: string } | null>(null)
const evidenceBusy = ref(false)
const evidenceMutation = ref('')
const evidenceError = ref('')
const appealBusy = ref(false)

watch(
  () => props.form_errors,
  (errors) => {
    supplementForm.clearErrors()
    if (!errors) return
    Object.entries(errors).forEach(([key, message]) => {
      supplementForm.setError(key as keyof typeof supplementForm.errors, message)
    })
  },
  { immediate: true },
)

watch(
  () => supplementForm.supplement.body,
  (body) => {
    const submitted = submittedSupplement.value
    if (!submitted || supplementForm.processing || body === submitted.body) return

    supplementForm.supplement.idempotency_key = createIdempotencyKey()
    submittedSupplement.value = null
  },
)

watch(
  () => props.report.lock_version,
  (version) => {
    supplementForm.supplement.lock_version = version
  },
)

const formError = computed(() => supplementForm.errors.base || props.form_errors?.base || '')
const supplementError = computed(() =>
  supplementForm.errors['supplement.body' as keyof typeof supplementForm.errors]
    || props.form_errors?.['supplement.body']
    || '',
)
const evidenceMessage = computed(() => evidenceError.value || props.form_errors?.evidence || '')
const activeEvidenceCount = computed(() => reportActiveEvidence(props.report.evidence_attachments))

function reportActiveEvidence(attachments: SecureEvidenceAttachment[]) {
  return attachments.filter((attachment) =>
    ['uploading', 'pending', 'available', 'quarantined'].includes(attachment.state),
  ).length
}

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

function statusLabel() {
  return statusLabels[props.report.status]()
}

function outcomeLabel() {
  const outcome = props.report.public_outcome_code
  return outcome ? outcomeLabels[outcome]() : t('forum.reports.outcome.pending')
}

function statusColor() {
  if (props.report.status === 'pending') return 'orange'
  if (props.report.status === 'actioned') return 'green'
  if (props.report.status === 'dismissed') return 'gray'
  return 'blue'
}

function responseHasFormErrors(page: { props: Record<string, unknown> }) {
  const errors = page.props.form_errors
  return Boolean(errors && typeof errors === 'object' && Object.keys(errors).length)
}

function addSupplement() {
  submittedSupplement.value = {
    body: supplementForm.supplement.body,
    key: supplementForm.supplement.idempotency_key,
  }
  supplementForm.post(props.report.supplement_url, {
    preserveScroll: true,
    onSuccess: (page) => {
      if (responseHasFormErrors(page)) return
      const submitted = submittedSupplement.value
      submittedSupplement.value = null
      if (submitted && supplementForm.supplement.body === submitted.body) {
        supplementForm.supplement.body = ''
      }
      supplementForm.supplement.idempotency_key = createIdempotencyKey()
    },
  })
}

async function withdrawReport() {
  const accepted = await confirm({
    title: t('forum.reports.withdrawTitle'),
    message: t('forum.reports.withdrawConfirm'),
    confirmLabel: t('forum.reports.withdraw'),
    cancelLabel: t('forum.reports.cancel'),
    variant: 'destructive',
  })
  if (!accepted) return

  router.patch(
    props.report.withdraw_url,
    {
      report: {
        desired_state: 'withdrawn',
        idempotency_key: withdrawalKey.value,
        lock_version: props.report.lock_version,
      },
    },
    {
      preserveScroll: true,
      onStart: () => { withdrawing.value = true },
      onSuccess: (page) => {
        if (!responseHasFormErrors(page)) withdrawalKey.value = createIdempotencyKey()
      },
      onFinish: () => { withdrawing.value = false },
    },
  )
}

function sealEvidence(attachment: SecureEvidenceAttachment) {
  evidenceError.value = ''
  router.post(
    props.report.evidence_url,
    { evidence: { attachment_public_ids: [attachment.public_id] } },
    {
      preserveScroll: true,
      onStart: () => { evidenceBusy.value = true },
      onFinish: () => { evidenceBusy.value = false },
    },
  )
}

async function discardEvidence(attachment: SecureEvidenceAttachment) {
  if (!attachment.discard_url) return

  evidenceMutation.value = attachment.public_id
  evidenceError.value = ''
  try {
    const response = await fetch(attachment.discard_url, {
      method: 'DELETE',
      headers: { ...csrfHeaders(), Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (!response.ok) throw new Error(t('forum.reportAppeals.evidence.discardFailed'))
    router.reload({ only: ['report', 'form_errors'] })
  } catch (cause) {
    evidenceError.value = cause instanceof Error && cause.message
      ? cause.message
      : t('forum.reportAppeals.evidence.discardFailed')
  } finally {
    evidenceMutation.value = ''
  }
}

function startAppeal(role: 'reporter') {
  router.post(
    props.report.appeal_draft_url,
    { appeal: { appellant_role: role, idempotency_key: createIdempotencyKey() } },
    {
      onStart: () => { appealBusy.value = true },
      onFinish: () => { appealBusy.value = false },
    },
  )
}
</script>

<template>
  <Head :title="t('forum.reports.caseReference', { id: report.id })">
    <meta name="robots" content="noindex,nofollow">
  </Head>

  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reports.caseReference', { id: report.id })"
      :subtitle="report.target_label"
      @back="router.visit(report.index_url)"
    >
      <template #breadcrumb>
        <Breadcrumb>
          <BreadcrumbItem><Link :href="routes.forum">{{ t('breadcrumb.forum') }}</Link></BreadcrumbItem>
          <BreadcrumbItem><Link :href="report.index_url">{{ t('forum.reports.caseCenter') }}</Link></BreadcrumbItem>
          <BreadcrumbItem>{{ t('forum.reports.caseReference', { id: report.id }) }}</BreadcrumbItem>
        </Breadcrumb>
      </template>
      <Space wrap>
        <Tag :color="statusColor()">{{ statusLabel() }}</Tag>
        <Button
          v-if="report.can_withdraw"
          type="outline"
          status="danger"
          :loading="withdrawing"
          :disabled="withdrawing"
          @click="withdrawReport"
        >
          {{ t('forum.reports.withdraw') }}
        </Button>
        <Button
          v-if="report.appeal_roles.includes('reporter')"
          type="primary"
          :loading="appealBusy"
          :disabled="appealBusy"
          @click="startAppeal('reporter')"
        >
          {{ t('forum.reportAppeals.requestReconsideration') }}
        </Button>
        <Button type="outline" @click="router.visit(report.appeals_url)">
          {{ t('forum.reportAppeals.history') }}
        </Button>
      </Space>
    </PageHeader>

    <Alert v-if="formError" type="error" show-icon aria-live="polite">
      {{ formError }}
    </Alert>
    <Alert
      :type="report.public_outcome_code ? 'info' : 'warning'"
      show-icon
      aria-live="polite"
    >
      {{ t('forum.reports.outcomeLabel', { outcome: outcomeLabel() }) }}
    </Alert>

    <Card :title="t('forum.reports.caseDetails')" :bordered="true">
      <Descriptions :column="1" :bordered="true">
        <DescriptionsItem :label="t('forum.reports.target')">{{ report.target_label }}</DescriptionsItem>
        <DescriptionsItem :label="t('forum.reports.reasonType')">{{ report.reason_label }}</DescriptionsItem>
        <DescriptionsItem :label="t('forum.reports.reasonDetail')">
          {{ report.reason_detail || t('forum.reports.noReasonDetail') }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('forum.reports.submitted')">{{ report.submitted_at }}</DescriptionsItem>
        <DescriptionsItem :label="t('forum.reports.lastChanged')">{{ report.state_changed_at }}</DescriptionsItem>
      </Descriptions>
    </Card>

    <Card :title="t('forum.reports.supplements')" :bordered="true">
      <List v-if="report.supplements.length" :bordered="false" :split="true">
        <ListItem v-for="supplement in report.supplements" :key="supplement.id">
          <Space direction="vertical" fill size="small">
            <TypographyParagraph>{{ supplement.body }}</TypographyParagraph>
            <TypographyText type="secondary">{{ supplement.created_at }}</TypographyText>
          </Space>
        </ListItem>
      </List>
      <Empty v-else :description="t('forum.reports.noSupplements')" />
    </Card>

    <Card
      v-if="report.can_supplement || report.evidence_attachments.length"
      :title="t('forum.reportAppeals.evidence.title')"
      :bordered="true"
    >
      <Alert v-if="evidenceMessage" type="error" show-icon aria-live="polite">{{ evidenceMessage }}</Alert>
      <List v-if="report.evidence_attachments.length" :bordered="false" :split="true">
        <ListItem v-for="attachment in report.evidence_attachments" :key="attachment.public_id">
          <Space direction="vertical" fill size="mini">
            <a
              v-if="attachment.state === 'available' && attachment.scan_status === 'clean'"
              :href="attachment.download_url"
            >{{ attachment.filename }}</a>
            <TypographyText v-else>{{ attachment.filename }}</TypographyText>
            <TypographyText type="secondary">
              {{ t(`forum.reportAppeals.evidence.state.${attachment.state}`) }}
            </TypographyText>
            <Space v-if="!attachment.sealed" wrap size="small">
              <Button
                v-if="attachment.state === 'available' && attachment.scan_status === 'clean'"
                type="primary"
                size="small"
                :loading="evidenceBusy"
                @click="sealEvidence(attachment)"
              >
                {{ t('forum.reportAppeals.evidence.attachToCase') }}
              </Button>
              <Button
                v-if="attachment.discard_url"
                type="text"
                status="danger"
                size="small"
                :loading="evidenceMutation === attachment.public_id"
                @click="discardEvidence(attachment)"
              >
                {{ t('forum.reportAppeals.evidence.discard') }}
              </Button>
            </Space>
          </Space>
        </ListItem>
      </List>
      <Empty v-else :description="t('forum.reportAppeals.evidence.empty')" />
      <SecureEvidenceUpload
        v-if="report.can_supplement"
        :upload-url="evidence_upload_url"
        :subject-key="report.evidence_subject.key"
        :subject-public-id="report.evidence_subject.public_id"
        :disabled="evidenceBusy || activeEvidenceCount >= 10"
        @uploaded="sealEvidence"
      />
    </Card>

    <Card v-if="report.can_supplement" :title="t('forum.reports.addSupplement')" :bordered="true">
      <Form :model="supplementForm.supplement" layout="vertical" @submit="addSupplement">
        <FormItem
          field="body"
          :label="t('forum.reports.supplementBody')"
          :help="supplementError"
          :validate-status="supplementError ? 'error' : undefined"
          required
        >
          <Textarea
            v-model="supplementForm.supplement.body"
            :max-length="2000"
            :placeholder="t('forum.reports.supplementPlaceholder')"
            :disabled="supplementForm.processing"
            show-word-limit
          />
        </FormItem>
        <Button
          type="primary"
          html-type="submit"
          :loading="supplementForm.processing"
          :disabled="supplementForm.processing"
        >
          {{ t('forum.reports.addSupplement') }}
        </Button>
      </Form>
    </Card>
  </Space>
</template>
