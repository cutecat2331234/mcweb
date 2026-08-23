<script setup lang="ts">
import { Head } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import StaffLayout from '@/layouts/StaffLayout.vue'
import ReportAppealReviewIndex from '@/components/community/ReportAppealReviewIndex.vue'
import { routes } from '@/lib/routes'
import type { ReportAppealPagination, ReportAppealReviewRow } from '@/types/communityReportAppeals'

defineOptions({ layout: StaffLayout })
const { t } = useI18n()
defineProps<{
  appeals: ReportAppealReviewRow[]
  pagination: ReportAppealPagination
  filters: { status?: string | null }
}>()
</script>

<template>
  <Head :title="t('forum.reportAppeals.review.title')" />
  <ReportAppealReviewIndex
    :appeals="appeals"
    :pagination="pagination"
    :filters="filters"
    :pagination-url="routes.staffReportAppeals"
  />
</template>
