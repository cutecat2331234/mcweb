<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

defineProps<{
  metrics: Array<{ label: string; value: number | string }>
  topPosters: Array<{ username: string; posts_count: number }>
  newestMembers: Array<{ username: string; joined_at: string }>
}>()

function metricNumber(value: number | string) {
  const numeric = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(numeric) ? numeric : 0
}

function isNumericMetric(value: number | string) {
  return Number.isFinite(typeof value === 'number' ? value : Number(value))
}

function metricPrecision(value: number | string) {
  if (typeof value !== 'string' || !value.includes('.')) return 0
  return value.split('.')[1]?.length ?? 0
}
</script>

<template>
  <a-page-header
    :title="t('admin.forumStatsPage.title')"
    :subtitle="t('admin.forumStatsPage.subtitle')"
    :show-back="false"
    class="mb-4 !px-0"
  />

  <a-row :gutter="[16, 16]" class="mb-6">
    <a-col v-for="metric in metrics" :key="metric.label" :xs="24" :sm="12" :lg="8">
      <a-card :bordered="true" hoverable>
        <a-statistic
          v-if="isNumericMetric(metric.value)"
          :title="metric.label"
          :value="metricNumber(metric.value)"
          :precision="metricPrecision(metric.value)"
        />
        <div v-else class="arco-statistic">
          <div class="arco-statistic-title">{{ metric.label }}</div>
          <div class="arco-statistic-content">{{ metric.value }}</div>
        </div>
      </a-card>
    </a-col>
  </a-row>

  <a-row :gutter="[16, 16]">
    <a-col :xs="24" :lg="12">
      <a-card :title="t('admin.forumStatsPage.topPosters')" :bordered="true">
        <a-table :data="topPosters" :pagination="false" row-key="username" stripe>
          <template #columns>
            <a-table-column :title="t('admin.forumStatsPage.colMember')" data-index="username">
              <template #cell="{ record }">@{{ record.username }}</template>
            </a-table-column>
            <a-table-column :title="t('admin.forumStatsPage.colPosts')" data-index="posts_count" />
          </template>
          <template #empty><a-empty :description="t('admin.forumStatsPage.empty')" /></template>
        </a-table>
      </a-card>
    </a-col>

    <a-col :xs="24" :lg="12">
      <a-card :title="t('admin.forumStatsPage.newestMembers')" :bordered="true">
        <a-table :data="newestMembers" :pagination="false" row-key="username" stripe>
          <template #columns>
            <a-table-column :title="t('admin.forumStatsPage.colMember')" data-index="username">
              <template #cell="{ record }">@{{ record.username }}</template>
            </a-table-column>
            <a-table-column :title="t('admin.forumStatsPage.colJoined')" data-index="joined_at" />
          </template>
          <template #empty><a-empty :description="t('admin.forumStatsPage.empty')" /></template>
        </a-table>
      </a-card>
    </a-col>
  </a-row>
</template>
