<script setup lang="ts">
import { Head } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
import ReportAppealReviewShow from '@/components/community/ReportAppealReviewShow.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import type { ReportAppealReviewDetail } from '@/types/communityReportAppeals'

defineOptions({ layout: ArcoAdminLayout })
const { t } = useI18n()
defineProps<{ appeal: ReportAppealReviewDetail }>()
</script>

<template>
  <Head :title="t('forum.reportAppeals.review.title')" />
  <ReportAppealReviewShow :appeal="appeal" :back-url="adminRoutes.forumReportAppeals" />
</template>
