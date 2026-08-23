<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

interface DetailField {
  label: string
  value: string
}

const props = defineProps<{
  title: string
  fields: DetailField[]
  backUrl: string
  approveUrl: string
  rejectUrl: string
  reasonMaxLength: number
}>()

const { t } = useI18n()
const rejectionOpen = ref(false)
const approvalConfirming = ref(false)
const localReasonError = ref('')
const approveForm = useForm({})
const rejectForm = useForm({ reason: '' })
const reasonError = computed(() => rejectForm.errors.reason || localReasonError.value)
const decisionBusy = computed(
  () => approvalConfirming.value || approveForm.processing || rejectForm.processing,
)

async function approve() {
  if (decisionBusy.value) return

  approvalConfirming.value = true
  let accepted = false
  try {
    accepted = await confirm({
      title: t('admin.forumApprovalReview.approveTitle'),
      message: t('admin.forumApprovalReview.approveConfirm'),
      confirmLabel: t('admin.forumApprovalReview.approve'),
    })
  } finally {
    approvalConfirming.value = false
  }
  if (!accepted) return

  approveForm.post(props.approveUrl)
}

function openRejection() {
  if (decisionBusy.value) return

  localReasonError.value = ''
  rejectForm.clearErrors()
  rejectionOpen.value = true
}

function closeRejection() {
  if (rejectForm.processing) return
  rejectionOpen.value = false
  localReasonError.value = ''
  rejectForm.reset()
  rejectForm.clearErrors()
}

function reject() {
  if (decisionBusy.value) return

  const reason = rejectForm.reason.trim()
  if (!reason) {
    localReasonError.value = t('admin.forumApprovalReview.reasonRequired')
    return
  }
  if (reason.length > props.reasonMaxLength) {
    localReasonError.value = t('admin.forumApprovalReview.reasonTooLong', {
      count: props.reasonMaxLength,
    })
    return
  }

  localReasonError.value = ''
  rejectForm.reason = reason
  rejectForm.post(props.rejectUrl)
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header :title="title" :show-back="false">
      <template #extra>
        <Link :href="backUrl">
          <a-button>{{ t('admin.forumApprovalReview.back') }}</a-button>
        </Link>
      </template>
    </a-page-header>

    <a-card :bordered="true">
      <a-descriptions :column="{ xs: 1, md: 2 }" bordered>
        <a-descriptions-item
          v-for="field in fields"
          :key="field.label"
          :label="field.label"
        >
          <a-typography-paragraph class="!mb-0 whitespace-pre-wrap">
            {{ field.value }}
          </a-typography-paragraph>
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-card :title="t('admin.forumApprovalReview.actions')" :bordered="true">
      <a-space direction="vertical" :size="16" fill>
        <a-space wrap>
          <a-button
            type="primary"
            :loading="approveForm.processing"
            :disabled="decisionBusy"
            @click="approve"
          >
            {{ t('admin.forumApprovalReview.approve') }}
          </a-button>
          <a-button
            type="primary"
            status="danger"
            :disabled="decisionBusy"
            @click="openRejection"
          >
            {{ t('admin.forumApprovalReview.reject') }}
          </a-button>
        </a-space>

        <a-form
          v-if="rejectionOpen"
          :model="rejectForm"
          layout="vertical"
          @submit="reject"
        >
          <a-alert
            type="warning"
            show-icon
            :closable="false"
            :title="t('admin.forumApprovalReview.rejectWarning')"
          />
          <a-form-item
            field="reason"
            :label="t('admin.forumApprovalReview.reason')"
            required
            :validate-status="reasonError ? 'error' : undefined"
            :help="reasonError || t('admin.forumApprovalReview.reasonHint')"
          >
            <a-textarea
              v-model="rejectForm.reason"
              :max-length="reasonMaxLength"
              show-word-limit
              :auto-size="{ minRows: 4, maxRows: 10 }"
              :disabled="decisionBusy"
            />
          </a-form-item>
          <a-space wrap>
            <a-button
              type="primary"
              status="danger"
              html-type="submit"
              :loading="rejectForm.processing"
              :disabled="decisionBusy"
            >
              {{ t('admin.forumApprovalReview.confirmReject') }}
            </a-button>
            <a-button
              html-type="button"
              :disabled="decisionBusy"
              @click="closeRejection"
            >
              {{ t('common.cancel') }}
            </a-button>
          </a-space>
        </a-form>
      </a-space>
    </a-card>
  </a-space>
</template>
