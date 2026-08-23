<script setup lang="ts">
import { Head } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import StaffLayout from '@/layouts/StaffLayout.vue'
import ReportAppealReviewShow from '@/components/community/ReportAppealReviewShow.vue'
import { routes } from '@/lib/routes'
import type { ReportAppealReviewDetail } from '@/types/communityReportAppeals'

defineOptions({ layout: StaffLayout })
const { t } = useI18n()
defineProps<{ appeal: ReportAppealReviewDetail }>()
</script>

<template>
  <Head :title="t('forum.reportAppeals.review.title')" />
  <ReportAppealReviewShow :appeal="appeal" :back-url="routes.staffReportAppeals" />
</template>
