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
  TypographyText,
} from '@mcweb/ui'
import PortalLayout from '@/layouts/PortalLayout.vue'
import SecureEvidenceUpload from '@/components/community/SecureEvidenceUpload.vue'
import type { SecureEvidenceAttachment } from '@/types/communityReportAppeals'
import { routes } from '@/lib/routes'
import { createIdempotencyKey } from '@/lib/idempotency'
import { csrfHeaders } from '@/lib/csrf'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: PortalLayout })

type AppealStatus = 'draft' | 'submitted' | 'under_review' | 'upheld' | 'overturned' | 'cancelled'

interface AppealDetail {
  public_id: string
  appellant_role: 'reporter' | 'affected_subject'
  status: AppealStatus
  public_outcome_code: 'upheld' | 'overturned' | 'cancelled' | null
  submitted_at: string | null
  state_changed_at: string
  expires_at: string | null
  reason: string | null
  lock_version: number
  report: { public_id: string; target_label: string; reason_label?: string }
  index_url: string
  submit_url: string
  cancel_url: string
  evidence_subject: { key: 'community.report_appeal'; public_id: string }
  attachments: SecureEvidenceAttachment[]
  events: Array<{
    type: string
    from_status: AppealStatus | null
    to_status: AppealStatus
    public_outcome_code: string | null
    occurred_at: string
  }>
  can_submit: boolean
  can_cancel: boolean
}

const props = defineProps<{
  appeal: AppealDetail
  evidence_upload_url: string
  form_errors?: Record<string, string> | null
}>()

const { t } = useI18n()
const cancelling = ref(false)
const discarding = ref('')
const evidenceError = ref('')
const form = useForm({
  appeal: {
    reason: props.appeal.reason || '',
    attachment_public_ids: props.appeal.attachments
      .filter((item) => item.state === 'available' && item.scan_status === 'clean')
      .map((item) => item.public_id),
    idempotency_key: createIdempotencyKey(),
    lock_version: props.appeal.lock_version,
  },
})

watch(() => props.appeal.lock_version, (value) => { form.appeal.lock_version = value })
watch(
  () => props.appeal.attachments,
  (attachments) => {
    form.appeal.attachment_public_ids = attachments
      .filter((item) => item.state === 'available' && item.scan_status === 'clean')
      .map((item) => item.public_id)
  },
  { deep: true },
)

const baseError = computed(() => form.errors.base || props.form_errors?.base || '')
const activeEvidenceCount = computed(() => props.appeal.attachments.filter((attachment) =>
  ['uploading', 'pending', 'available', 'quarantined'].includes(attachment.state),
).length)

function submitAppeal() {
  form.patch(props.appeal.submit_url, {
    preserveScroll: true,
    onSuccess: () => { form.appeal.idempotency_key = createIdempotencyKey() },
  })
}

async function cancelAppeal() {
  const accepted = await confirm({
    title: t('forum.reportAppeals.cancelTitle'),
    message: t('forum.reportAppeals.cancelConfirm'),
    confirmLabel: t('forum.reportAppeals.cancel'),
    cancelLabel: t('common.cancel'),
    variant: 'destructive',
  })
  if (!accepted) return

  router.patch(
    props.appeal.cancel_url,
    { appeal: { idempotency_key: createIdempotencyKey(), lock_version: props.appeal.lock_version } },
    {
      onStart: () => { cancelling.value = true },
      onFinish: () => { cancelling.value = false },
    },
  )
}

function refreshAttachments() {
  router.reload({ only: ['appeal', 'form_errors'] })
}

async function discardAttachment(attachment: SecureEvidenceAttachment) {
  if (!attachment.discard_url) return
  discarding.value = attachment.public_id
  evidenceError.value = ''
  try {
    const response = await fetch(attachment.discard_url, {
      method: 'DELETE',
      headers: { ...csrfHeaders(), Accept: 'application/json' },
      credentials: 'same-origin',
    })
    if (!response.ok) throw new Error(t('forum.reportAppeals.evidence.discardFailed'))
    refreshAttachments()
  } catch (cause) {
    evidenceError.value = cause instanceof Error && cause.message
      ? cause.message
      : t('forum.reportAppeals.evidence.discardFailed')
  } finally {
    discarding.value = ''
  }
}
</script>

<template>
  <Head :title="t('forum.reportAppeals.reference', { id: appeal.public_id })">
    <meta name="robots" content="noindex,nofollow">
  </Head>

  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reportAppeals.reference', { id: appeal.public_id })"
      :subtitle="appeal.report.target_label"
      @back="router.visit(appeal.index_url)"
    >
      <template #breadcrumb>
        <Breadcrumb>
          <BreadcrumbItem><Link :href="routes.forum">{{ t('breadcrumb.forum') }}</Link></BreadcrumbItem>
          <BreadcrumbItem><Link :href="appeal.index_url">{{ t('forum.reportAppeals.navigation') }}</Link></BreadcrumbItem>
          <BreadcrumbItem>{{ t('forum.reportAppeals.reference', { id: appeal.public_id }) }}</BreadcrumbItem>
        </Breadcrumb>
      </template>
      <Space wrap>
        <Tag>{{ t(`forum.reportAppeals.roles.${appeal.appellant_role}`) }}</Tag>
        <Tag color="blue">{{ t(`forum.reportAppeals.status.${appeal.status}`) }}</Tag>
        <Button
          v-if="appeal.can_cancel"
          type="outline"
          status="danger"
          :loading="cancelling"
          @click="cancelAppeal"
        >
          {{ t('forum.reportAppeals.cancel') }}
        </Button>
      </Space>
    </PageHeader>

    <Alert v-if="baseError" type="error" show-icon aria-live="polite">{{ baseError }}</Alert>
    <Alert v-if="appeal.public_outcome_code" type="info" show-icon>
      {{ t(`forum.reportAppeals.outcome.${appeal.public_outcome_code}`) }}
    </Alert>

    <Card :title="t('forum.reportAppeals.details')" :bordered="true">
      <Descriptions :column="1" :bordered="true">
        <DescriptionsItem :label="t('forum.reports.target')">{{ appeal.report.target_label }}</DescriptionsItem>
        <DescriptionsItem v-if="appeal.report.reason_label" :label="t('forum.reports.reasonType')">
          {{ appeal.report.reason_label }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('forum.reportAppeals.role')">
          {{ t(`forum.reportAppeals.roles.${appeal.appellant_role}`) }}
        </DescriptionsItem>
        <DescriptionsItem v-if="appeal.reason" :label="t('forum.reportAppeals.reason')">
          {{ appeal.reason }}
        </DescriptionsItem>
        <DescriptionsItem v-if="appeal.expires_at" :label="t('forum.reportAppeals.draftExpires')">
          {{ appeal.expires_at }}
        </DescriptionsItem>
      </Descriptions>
    </Card>

    <Card :title="t('forum.reportAppeals.evidence.title')" :bordered="true">
      <Alert v-if="evidenceError" type="error" show-icon aria-live="polite">{{ evidenceError }}</Alert>
      <List v-if="appeal.attachments.length" :bordered="false" :split="true">
        <ListItem v-for="attachment in appeal.attachments" :key="attachment.public_id">
          <Space direction="vertical" fill size="mini">
            <a
              v-if="attachment.state === 'available' && attachment.scan_status === 'clean'"
              :href="attachment.download_url"
            >
              {{ attachment.filename }}
            </a>
            <TypographyText v-else>{{ attachment.filename }}</TypographyText>
            <TypographyText type="secondary">
              {{ t(`forum.reportAppeals.evidence.state.${attachment.state}`) }}
            </TypographyText>
            <Button
              v-if="attachment.discard_url"
              type="text"
              status="danger"
              size="small"
              :loading="discarding === attachment.public_id"
              @click="discardAttachment(attachment)"
            >
              {{ t('forum.reportAppeals.evidence.discard') }}
            </Button>
          </Space>
        </ListItem>
      </List>
      <Empty v-else :description="t('forum.reportAppeals.evidence.empty')" />
      <SecureEvidenceUpload
        v-if="appeal.can_submit"
        :upload-url="evidence_upload_url"
        :subject-key="appeal.evidence_subject.key"
        :subject-public-id="appeal.evidence_subject.public_id"
        :disabled="activeEvidenceCount >= 10"
        @uploaded="refreshAttachments"
      />
    </Card>

    <Card v-if="appeal.can_submit" :title="t('forum.reportAppeals.submitTitle')" :bordered="true">
      <Form :model="form.appeal" layout="vertical" @submit="submitAppeal">
        <FormItem field="reason" :label="t('forum.reportAppeals.reason')" required>
          <Textarea
            v-model="form.appeal.reason"
            :max-length="5000"
            show-word-limit
            :placeholder="t('forum.reportAppeals.reasonPlaceholder')"
            :disabled="form.processing"
          />
        </FormItem>
        <Button type="primary" html-type="submit" :loading="form.processing">
          {{ t('forum.reportAppeals.submit') }}
        </Button>
      </Form>
    </Card>

    <Card :title="t('forum.reportAppeals.timeline')" :bordered="true">
      <List v-if="appeal.events.length" :bordered="false" :split="true">
        <ListItem v-for="event in appeal.events" :key="`${event.type}-${event.occurred_at}`">
          <Space direction="vertical" fill size="mini">
            <TypographyText>{{ t(`forum.reportAppeals.events.${event.type}`) }}</TypographyText>
            <TypographyText type="secondary">{{ event.occurred_at }}</TypographyText>
          </Space>
        </ListItem>
      </List>
      <Empty v-else :description="t('forum.reportAppeals.timelineEmpty')" />
    </Card>
  </Space>
</template>
