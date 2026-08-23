<script setup lang="ts">
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import SharedSecureEvidenceUpload from '@/components/secure-evidence/SecureEvidenceUpload.vue'
import type { SecureEvidenceAttachment } from '@/types/communityReportAppeals'

defineProps<{
  uploadUrl: string
  subjectKey: 'community.report' | 'community.report_appeal'
  subjectPublicId: string
  disabled?: boolean
}>()

const emit = defineEmits<{
  uploaded: [attachment: SecureEvidenceAttachment]
}>()

const { t } = useI18n()
const copy = computed(() => ({
  add: t('forum.reportAppeals.evidence.add'),
  processing: t('forum.reportAppeals.evidence.processing'),
  limit: t('forum.reportAppeals.evidence.limit'),
  uploadFailed: t('forum.reportAppeals.evidence.uploadFailed'),
  scanFailed: t('forum.reportAppeals.evidence.scanFailed'),
  scanTimeout: t('forum.reportAppeals.evidence.scanTimeout'),
}))
</script>

<template>
  <SharedSecureEvidenceUpload
    :upload-url="uploadUrl"
    :subject-key="subjectKey"
    :subject-public-id="subjectPublicId"
    :copy="copy"
    :disabled="disabled"
    @uploaded="emit('uploaded', $event)"
  />
</template>
