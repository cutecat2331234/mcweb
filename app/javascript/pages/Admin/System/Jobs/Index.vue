<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  dashboardUrl: string
  developerMode: {
    enabled: boolean
    profile?: string | null
  }
  automaticRegistration: boolean
}>()
</script>

<template>
  <section>
    <a-page-header
      :title="t('admin.jobsPage.title')"
      :subtitle="t('admin.jobsPage.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-alert
      v-if="developerMode.enabled"
      type="warning"
      show-icon
      :title="t('admin.jobsPage.developerModeTitle')"
      class="mb-4"
    >
      {{ t('admin.jobsPage.developerModeDescription') }}
    </a-alert>

    <div class="grid gap-4 lg:grid-cols-2">
      <a-card :title="t('admin.jobsPage.schedulerTitle')" :bordered="true">
        <a-descriptions :column="1" bordered size="small">
          <a-descriptions-item :label="t('admin.jobsPage.runtimeMode')">
            <a-space wrap>
              <a-tag :color="developerMode.enabled ? 'orange' : 'green'">
                {{
                  developerMode.enabled
                    ? t('admin.jobsPage.developerMode')
                    : t('admin.jobsPage.standardMode')
                }}
              </a-tag>
              <span v-if="developerMode.profile">{{ developerMode.profile }}</span>
            </a-space>
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.jobsPage.automaticRegistration')">
            <a-tag :color="automaticRegistration ? 'green' : 'orange'">
              {{
                automaticRegistration
                  ? t('admin.jobsPage.running')
                  : t('admin.jobsPage.paused')
              }}
            </a-tag>
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.jobsPage.manualExecution')">
            <a-tag color="green">{{ t('admin.jobsPage.available') }}</a-tag>
          </a-descriptions-item>
        </a-descriptions>
      </a-card>

      <a-card :title="t('admin.jobsPage.dashboardTitle')" :bordered="true">
        <p class="mb-4 text-sm text-[var(--color-text-2)]">
          {{ t('admin.jobsPage.dashboardDescription') }}
        </p>
        <a-button type="primary" :href="dashboardUrl" data-admin-hard-navigation>
          {{ t('admin.jobsPage.openDashboard') }}
        </a-button>
      </a-card>
    </div>
  </section>
</template>
