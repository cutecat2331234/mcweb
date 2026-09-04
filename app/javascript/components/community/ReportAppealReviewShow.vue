<script setup lang="ts">
import { computed, ref } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
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
  Select,
  Option,
  Space,
  Tag,
  Textarea,
  TypographyText,
} from '@mcweb/ui'
import { createIdempotencyKey } from '@/lib/idempotency'
import { csrfHeaders } from '@/lib/csrf'
import SecureEvidenceUpload from '@/components/community/SecureEvidenceUpload.vue'
import type { ReportAppealReviewDetail, SecureEvidenceAttachment } from '@/types/communityReportAppeals'

const props = defineProps<{
  appeal: ReportAppealReviewDetail
  backUrl: string
}>()

const { t } = useI18n()
const evidenceBusy = ref(false)
const evidenceMutation = ref('')
const evidenceError = ref('')
const form = useForm({
  appeal: {
    decision: 'upheld',
    internal_note: '',
    idempotency_key: createIdempotencyKey(),
    lock_version: props.appeal.lock_version,
  },
})
const activeEvidenceCount = computed(() => props.appeal.attachments.filter((attachment) =>
  ['uploading', 'pending', 'available', 'quarantined'].includes(attachment.state),
).length)

function decide() {
  form.patch(props.appeal.decision_url)
}

function sealEvidence(attachment: SecureEvidenceAttachment) {
  if (!props.appeal.evidence_url) return
  evidenceError.value = ''
  router.post(
    props.appeal.evidence_url,
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
    router.reload({ only: ['appeal'] })
  } catch (cause) {
    evidenceError.value = cause instanceof Error && cause.message
      ? cause.message
      : t('forum.reportAppeals.evidence.discardFailed')
  } finally {
    evidenceMutation.value = ''
  }
}

function retrySeal(attachment: SecureEvidenceAttachment) {
  sealEvidence(attachment)
}
</script>

<template>
  <Space direction="vertical" fill size="large">
    <PageHeader
      :title="t('forum.reportAppeals.reference', { id: appeal.public_id })"
      :subtitle="appeal.report_target"
      @back="router.visit(backUrl)"
    >
      <Space wrap>
        <Tag>{{ t(`forum.reportAppeals.roles.${appeal.appellant_role}`) }}</Tag>
        <Tag color="blue">{{ t(`forum.reportAppeals.status.${appeal.status}`) }}</Tag>
      </Space>
    </PageHeader>

    <Alert v-if="form.errors.base" type="error" show-icon aria-live="polite">{{ form.errors.base }}</Alert>

    <Card :title="t('forum.reportAppeals.review.publicCase')" :bordered="true">
      <Descriptions :column="1" :bordered="true">
        <DescriptionsItem :label="t('forum.reportAppeals.review.appellant')">{{ appeal.appellant }}</DescriptionsItem>
        <DescriptionsItem :label="t('forum.reportAppeals.reason')">{{ appeal.public_case.reason }}</DescriptionsItem>
        <DescriptionsItem :label="t('forum.reportAppeals.review.submittedAt')">{{ appeal.submitted_at }}</DescriptionsItem>
      </Descriptions>
    </Card>

    <Card :title="t('forum.reportAppeals.review.internalCase')" :bordered="true">
      <Descriptions :column="1" :bordered="true">
        <DescriptionsItem :label="t('forum.reportAppeals.review.reportReference')">
          {{ appeal.internal_case.report_public_id }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('forum.reports.reasonType')">
          {{ appeal.internal_case.report_reason_label }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('forum.reports.reasonDetail')">
          {{ appeal.internal_case.report_reason_detail || t('forum.reports.noReasonDetail') }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('forum.reportAppeals.review.reporter')">
          {{ appeal.internal_case.reporter }}
        </DescriptionsItem>
        <DescriptionsItem :label="t('forum.reportAppeals.review.affectedUser')">
          {{ appeal.internal_case.affected_user || t('common.notAvailable') }}
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
            >{{ attachment.filename }}</a>
            <TypographyText v-else>{{ attachment.filename }}</TypographyText>
            <Tag>{{ t(`forum.reportAppeals.evidence.state.${attachment.state}`) }}</Tag>
            <Tag v-if="attachment.audience">
              {{ t(`forum.reportAppeals.evidence.audience.${attachment.audience}`) }}
            </Tag>
            <Space v-if="!attachment.sealed" wrap size="small">
              <Button
                v-if="attachment.state === 'available' && attachment.scan_status === 'clean'"
                type="primary"
                size="small"
                :loading="evidenceBusy"
                @click="retrySeal(attachment)"
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
        v-if="appeal.can_add_evidence"
        :upload-url="appeal.evidence_upload_url"
        :subject-key="appeal.evidence_subject.key"
        :subject-public-id="appeal.evidence_subject.public_id"
        :disabled="evidenceBusy || activeEvidenceCount >= 10"
        @uploaded="sealEvidence"
      />
    </Card>

    <Card v-if="appeal.can_decide" :title="t('forum.reportAppeals.review.decision')" :bordered="true">
      <Form :model="form.appeal" layout="vertical" @submit="decide">
        <FormItem field="decision" :label="t('forum.reportAppeals.review.decision')" required>
          <Select v-model="form.appeal.decision">
            <Option value="upheld">{{ t('forum.reportAppeals.review.uphold') }}</Option>
            <Option value="overturned">{{ t('forum.reportAppeals.review.overturn') }}</Option>
          </Select>
        </FormItem>
        <FormItem field="internal_note" :label="t('forum.reportAppeals.review.internalNote')">
          <Textarea v-model="form.appeal.internal_note" :max-length="5000" show-word-limit />
        </FormItem>
        <Alert type="warning" show-icon>{{ t('forum.reportAppeals.review.noAutomaticReversal') }}</Alert>
        <Button type="primary" html-type="submit" :loading="form.processing">
          {{ t('forum.reportAppeals.review.submitDecision') }}
        </Button>
      </Form>
    </Card>
  </Space>
</template>
