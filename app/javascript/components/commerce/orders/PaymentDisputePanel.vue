<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  Alert,
  Button,
  Card,
  Empty,
  Form,
  FormItem,
  InputNumber,
  List,
  ListItem,
  Option,
  Select,
  Space,
  Tag,
  Textarea,
  Timeline,
  TimelineItem,
  TypographyParagraph,
  TypographyText,
} from '@mcweb/ui'
import SharedSecureEvidenceUpload from '@/components/secure-evidence/SecureEvidenceUpload.vue'
import { confirm as arcoConfirm } from '@/lib/arcoConfirm'
import { createIdempotencyKey } from '@/lib/idempotency'
import messages from '@/locales/commercePaymentDisputes'
import type { CustomerPaymentDisputes } from '@/types/commercePaymentDisputes'

const props = defineProps<{ paymentDisputes: CustomerPaymentDisputes }>()

const { t } = useI18n({ useScope: 'local', messages })
const createForm = useForm({
  dispute: {
    request_id: createIdempotencyKey(),
    reason_kind: '',
    description: '',
    amount_cents: props.paymentDisputes.create.max_amount_cents,
  },
})
const withdrawingId = ref('')
const withdrawalRequestIds = new Map<string, string>()

const uploadCopy = computed(() => ({
  add: t('evidenceAdd'),
  processing: t('evidenceProcessing'),
  limit: t('evidenceLimit'),
  uploadFailed: t('evidenceUploadFailed'),
  scanFailed: t('evidenceScanFailed'),
  scanTimeout: t('evidenceScanTimeout'),
}))

watch(
  () => props.paymentDisputes.create.max_amount_cents,
  (amount) => {
    if (!createForm.processing) createForm.dispute.amount_cents = amount
  },
)

function submitCreate() {
  createForm.post(props.paymentDisputes.create.url, {
    preserveScroll: true,
    onSuccess: (page) => {
      const next = page.props.paymentDisputes as CustomerPaymentDisputes | undefined
      if (!next || next.create.allowed) return

      createForm.dispute.request_id = createIdempotencyKey()
      createForm.dispute.reason_kind = ''
      createForm.dispute.description = ''
    },
  })
}

function refreshCases() {
  router.reload({ only: ['paymentDisputes'], preserveScroll: true, preserveState: true })
}

function activeEvidenceCount(item: CustomerPaymentDisputes['cases'][number]) {
  return item.attachments.filter((attachment) =>
    ['uploading', 'pending', 'available', 'quarantined'].includes(attachment.state),
  ).length
}

async function withdrawCase(item: CustomerPaymentDisputes['cases'][number]) {
  if (!item.can_withdraw || !item.withdraw_url) return
  const approved = await arcoConfirm({
    title: t('withdrawTitle'),
    message: t('withdrawConfirm'),
    confirmLabel: t('withdrawAction'),
    variant: 'destructive',
  })
  if (!approved) return

  withdrawingId.value = item.public_id
  const requestId = withdrawalRequestIds.get(item.public_id) || createIdempotencyKey()
  withdrawalRequestIds.set(item.public_id, requestId)
  router.delete(item.withdraw_url, {
    data: {
      dispute: {
        request_id: requestId,
        withdraw_reason: '',
      },
    },
    preserveScroll: true,
    onSuccess: (page) => {
      const next = page.props.paymentDisputes as CustomerPaymentDisputes | undefined
      const nextCase = next?.cases.find((entry) => entry.public_id === item.public_id)
      if (!nextCase?.can_withdraw) withdrawalRequestIds.delete(item.public_id)
    },
    onFinish: () => { withdrawingId.value = '' },
  })
}

function statusColor(status: string) {
  if (status === 'won' || status === 'withdrawn' || status === 'closed') return 'green'
  if (status === 'lost') return 'red'
  if (status === 'under_review' || status === 'evidence_submitted') return 'arcoblue'
  return 'orange'
}
</script>

<template>
  <Card :title="t('title')" :bordered="true" class="mb-6">
    <Space direction="vertical" size="large" fill>
      <TypographyParagraph type="secondary">{{ t('subtitle') }}</TypographyParagraph>

      <Card v-if="paymentDisputes.create.allowed" :title="t('openTitle')" :bordered="true">
        <Alert type="info" show-icon>{{ t('openHint') }}</Alert>
        <Form :model="createForm.dispute" layout="vertical" @submit="submitCreate">
          <FormItem field="reason_kind" :label="t('reason')" required>
            <Select v-model="createForm.dispute.reason_kind" :placeholder="t('chooseReason')">
              <Option
                v-for="option in paymentDisputes.create.reason_options"
                :key="option.value"
                :value="option.value"
              >
                {{ option.label }}
              </Option>
            </Select>
          </FormItem>
          <FormItem field="amount_cents" :label="t('amount')" required>
            <InputNumber
              v-model="createForm.dispute.amount_cents"
              :min="1"
              :max="paymentDisputes.create.max_amount_cents"
              :precision="0"
            />
            <TypographyText type="secondary">
              {{ t('amountHint', { amount: paymentDisputes.create.max_amount_label }) }}
            </TypographyText>
          </FormItem>
          <FormItem field="description" :label="t('description')" required>
            <Textarea
              v-model="createForm.dispute.description"
              :min-length="paymentDisputes.create.description_min_length"
              :max-length="paymentDisputes.create.description_max_length"
              :placeholder="t('descriptionPlaceholder')"
              show-word-limit
            />
          </FormItem>
          <Button
            type="primary"
            html-type="submit"
            :loading="createForm.processing"
            :disabled="createForm.processing || !createForm.dispute.reason_kind || createForm.dispute.description.trim().length < paymentDisputes.create.description_min_length"
          >
            {{ t('submit') }}
          </Button>
        </Form>
      </Card>

      <Empty v-if="paymentDisputes.cases.length === 0" :description="t('noCases')" />
      <template v-else>
        <Card
          v-for="item in paymentDisputes.cases"
          :key="item.public_id"
          :title="t('caseTitle', { id: item.public_id })"
          :bordered="true"
        >
          <Space direction="vertical" fill>
            <Space wrap>
              <Tag :color="statusColor(item.status)">{{ item.status_label }}</Tag>
              <TypographyText>{{ t('amountValue', { amount: item.amount_label }) }}</TypographyText>
              <TypographyText type="secondary">
                {{ t('rightsValue', { status: item.rights_status_label }) }}
              </TypographyText>
            </Space>
            <Alert
              v-if="item.rights_status === 'frozen' || item.rights_status === 'revoked'"
              type="warning"
              show-icon
            >
              {{ t('rightsHeld') }}
            </Alert>
            <Alert v-if="item.evidence_due_at" type="warning" show-icon>
              {{ t('evidenceDue', { time: item.evidence_due_at }) }}
            </Alert>

            <Card :title="t('evidenceTitle')" :bordered="false">
              <List v-if="item.attachments.length" :bordered="false" :split="true">
                <ListItem v-for="attachment in item.attachments" :key="attachment.public_id">
                  <Space direction="vertical" size="mini" fill>
                    <Space wrap>
                      <TypographyText bold>{{ attachment.filename }}</TypographyText>
                      <Tag>{{ attachment.status_label }}</Tag>
                    </Space>
                    <TypographyText type="secondary">
                      {{ attachment.byte_size_label }} · {{ attachment.created_at }}
                    </TypographyText>
                    <a
                      v-if="attachment.download_url"
                      :href="attachment.download_url"
                      class="text-primary hover:underline"
                    >
                      {{ t('download') }}
                    </a>
                  </Space>
                </ListItem>
              </List>
              <Empty v-else :description="t('evidenceEmpty')" />
              <SharedSecureEvidenceUpload
                v-if="item.can_upload_evidence"
                class="mt-3"
                :upload-url="paymentDisputes.upload_url"
                :subject-key="item.evidence_subject.key"
                :subject-public-id="item.evidence_subject.public_id"
                :copy="uploadCopy"
                :disabled="activeEvidenceCount(item) >= paymentDisputes.evidence_limits.max_files"
                @uploaded="refreshCases"
              />
            </Card>

            <Card :title="t('timelineTitle')" :bordered="false">
              <Timeline>
                <TimelineItem
                  v-for="entry in item.timeline"
                  :key="entry.key"
                  :dot-color="statusColor(entry.status || item.status)"
                >
                  <TypographyText bold>{{ entry.label }}</TypographyText>
                  <TypographyParagraph v-if="entry.description">
                    {{ entry.description }}
                  </TypographyParagraph>
                  <TypographyText type="secondary">{{ entry.occurred_at }}</TypographyText>
                </TimelineItem>
              </Timeline>
            </Card>

            <Button
              v-if="item.can_withdraw && item.withdraw_url"
              status="danger"
              type="outline"
              :loading="withdrawingId === item.public_id"
              @click="withdrawCase(item)"
            >
              {{ t('withdraw') }}
            </Button>
          </Space>
        </Card>
      </template>
    </Space>
  </Card>
</template>
