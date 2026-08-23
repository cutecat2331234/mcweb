<script setup lang="ts">
import { Head } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import ArcoAdminLayout from '@/layouts/ArcoAdminLayout.vue'
import ReportAppealReviewIndex from '@/components/community/ReportAppealReviewIndex.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import type { ReportAppealPagination, ReportAppealReviewRow } from '@/types/communityReportAppeals'

defineOptions({ layout: ArcoAdminLayout })
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
    :pagination-url="adminRoutes.forumReportAppeals"
  />
</template>
