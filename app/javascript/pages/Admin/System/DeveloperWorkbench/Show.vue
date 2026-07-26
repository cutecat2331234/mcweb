<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

interface ConfigurationEntry {
  key: string
  value: string
}

interface CaptureEntry {
  captureRef?: string
  capturedAt: string
  sizeBytes?: number
  method?: string
  notificationType?: string
}

interface CaptureSummary {
  relativeDirectory: string
  exists: boolean
  fileCount: number
  totalBytes: number
  truncated: boolean
  latestEntries: CaptureEntry[]
}

interface MinecraftTask {
  taskType: string
  status: string
  createdAt: string | null
  completedAt: string | null
}

interface Props {
  profile: string
  productionEnvironment: boolean
  autoLoginConfigured: boolean
  automaticRegistration: boolean
  configuration: {
    security: ConfigurationEntry[]
    integrations: ConfigurationEntry[]
    runtime: ConfigurationEntry[]
  }
  captures: {
    mail: CaptureSummary
    webhooks: CaptureSummary
    webPush: CaptureSummary
  }
  minecraft: {
    available: boolean
    total: number
    pending: number
    claimed: number
    completed: number
    failed: number
    recent: MinecraftTask[]
  }
  settingsUrl: string
  jobsUrl: string
}

const props = defineProps<Props>()
const { locale, t } = useI18n()

const configurationGroups = computed(() => [
  {
    key: 'security',
    title: t('admin.developerWorkbench.configuration.security'),
    entries: props.configuration.security,
    color: 'orangered',
  },
  {
    key: 'integrations',
    title: t('admin.developerWorkbench.configuration.integrations'),
    entries: props.configuration.integrations,
    color: 'arcoblue',
  },
  {
    key: 'runtime',
    title: t('admin.developerWorkbench.configuration.runtime'),
    entries: props.configuration.runtime,
    color: 'purple',
  },
])

const captureGroups = computed(() => [
  {
    key: 'mail',
    title: t('admin.developerWorkbench.captures.mail'),
    summary: props.captures.mail,
  },
  {
    key: 'webhooks',
    title: t('admin.developerWorkbench.captures.webhooks'),
    summary: props.captures.webhooks,
  },
  {
    key: 'webPush',
    title: t('admin.developerWorkbench.captures.webPush'),
    summary: props.captures.webPush,
  },
])

function visit(url: string) {
  router.visit(url)
}

function configurationLabel(key: string) {
  return t(`admin.developerWorkbench.configKeys.${key}`, key)
}

function configurationValue(value: string) {
  return t(`admin.developerWorkbench.configValues.${value}`, value)
}

function formatTime(value: string | null) {
  if (!value) return t('admin.developerWorkbench.notAvailable')

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return t('admin.developerWorkbench.notAvailable')

  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'medium',
  }).format(date)
}

function formatBytes(value: number) {
  if (value < 1024) return t('admin.developerWorkbench.bytes', { count: value })
  if (value < 1024 * 1024) {
    return t('admin.developerWorkbench.kibibytes', {
      count: (value / 1024).toFixed(1),
    })
  }

  return t('admin.developerWorkbench.mebibytes', {
    count: (value / 1024 / 1024).toFixed(1),
  })
}

function captureDetail(kind: string, entry: CaptureEntry) {
  if (kind === 'mail') return t('admin.developerWorkbench.captures.mailMessage')
  if (kind === 'webhooks') {
    return t('admin.developerWorkbench.captures.webhookEntry', {
      method: entry.method ?? t('admin.developerWorkbench.notAvailable'),
      reference: entry.captureRef ?? t('admin.developerWorkbench.notAvailable'),
    })
  }

  return t('admin.developerWorkbench.captures.webPushEntry', {
    type: entry.notificationType ?? t('admin.developerWorkbench.notAvailable'),
    reference: entry.captureRef ?? t('admin.developerWorkbench.notAvailable'),
  })
}

function statusColor(status: string) {
  if (status === 'completed') return 'green'
  if (status === 'failed') return 'red'
  if (status === 'claimed') return 'arcoblue'
  return 'orange'
}
</script>

<template>
  <section>
    <a-page-header
      :title="t('admin.developerWorkbench.title')"
      :subtitle="t('admin.developerWorkbench.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    >
      <template #extra>
        <a-space wrap>
          <a-button @click="visit(settingsUrl)">
            {{ t('admin.developerWorkbench.openSettings') }}
          </a-button>
          <a-button type="primary" @click="visit(jobsUrl)">
            {{ t('admin.developerWorkbench.openJobs') }}
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-alert
      v-if="productionEnvironment"
      type="error"
      show-icon
      :title="t('admin.developerWorkbench.productionWarningTitle')"
      class="mb-4"
    >
      {{ t('admin.developerWorkbench.productionWarningDescription') }}
    </a-alert>

    <a-alert
      type="warning"
      show-icon
      :title="t('admin.developerWorkbench.readOnlyTitle')"
      class="mb-4"
    >
      {{ t('admin.developerWorkbench.readOnlyDescription') }}
    </a-alert>

    <a-card :title="t('admin.developerWorkbench.overview')" class="mb-4">
      <a-descriptions :column="{ xs: 1, md: 2, lg: 4 }" bordered size="small">
        <a-descriptions-item :label="t('admin.developerWorkbench.profile')">
          <a-tag color="orangered">{{ configurationValue(profile) }}</a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.developerWorkbench.environment')">
          <a-tag :color="productionEnvironment ? 'red' : 'green'">
            {{
              productionEnvironment
                ? t('admin.developerWorkbench.production')
                : t('admin.developerWorkbench.nonProduction')
            }}
          </a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.developerWorkbench.autoLogin')">
          <a-tag :color="autoLoginConfigured ? 'orange' : 'gray'">
            {{
              autoLoginConfigured
                ? t('admin.developerWorkbench.configured')
                : t('admin.developerWorkbench.notConfigured')
            }}
          </a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.developerWorkbench.cronRegistration')">
          <a-tag :color="automaticRegistration ? 'green' : 'orange'">
            {{
              automaticRegistration
                ? t('admin.developerWorkbench.active')
                : t('admin.developerWorkbench.paused')
            }}
          </a-tag>
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-typography-title :heading="5" class="mb-3">
      {{ t('admin.developerWorkbench.activeConfiguration') }}
    </a-typography-title>
    <a-grid :cols="{ xs: 1, lg: 3 }" :col-gap="16" :row-gap="16" class="mb-4">
      <a-grid-item v-for="group in configurationGroups" :key="group.key">
        <a-card :title="group.title">
          <a-table
            :data="group.entries"
            :pagination="false"
            row-key="key"
            size="small"
          >
            <template #columns>
              <a-table-column
                :title="t('admin.developerWorkbench.configuration.option')"
                data-index="key"
              >
                <template #cell="{ record }">
                  {{ configurationLabel(record.key) }}
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.developerWorkbench.configuration.value')"
                data-index="value"
                :width="132"
              >
                <template #cell="{ record }">
                  <a-tag :color="group.color">
                    {{ configurationValue(record.value) }}
                  </a-tag>
                </template>
              </a-table-column>
            </template>
            <template #empty>
              <a-empty :description="t('admin.developerWorkbench.noActiveConfiguration')" />
            </template>
          </a-table>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-typography-title :heading="5" class="mb-3">
      {{ t('admin.developerWorkbench.captures.title') }}
    </a-typography-title>
    <a-alert
      type="info"
      show-icon
      :title="t('admin.developerWorkbench.captures.privacyTitle')"
      class="mb-3"
    >
      {{ t('admin.developerWorkbench.captures.privacyDescription') }}
    </a-alert>
    <a-grid :cols="{ xs: 1, xl: 3 }" :col-gap="16" :row-gap="16" class="mb-4">
      <a-grid-item v-for="capture in captureGroups" :key="capture.key">
        <a-card :title="capture.title">
          <a-descriptions :column="1" bordered size="small" class="mb-3">
            <a-descriptions-item :label="t('admin.developerWorkbench.captures.directory')">
              <a-typography-text code>
                {{ capture.summary.relativeDirectory }}
              </a-typography-text>
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.developerWorkbench.captures.files')">
              {{ capture.summary.fileCount }}
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.developerWorkbench.captures.size')">
              {{ formatBytes(capture.summary.totalBytes) }}
            </a-descriptions-item>
          </a-descriptions>

          <a-alert
            v-if="capture.summary.truncated"
            type="warning"
            :title="t('admin.developerWorkbench.captures.truncated')"
            class="mb-3"
          />

          <a-table
            :data="capture.summary.latestEntries"
            :pagination="false"
            row-key="capturedAt"
            size="small"
          >
            <template #columns>
              <a-table-column
                :title="t('admin.developerWorkbench.captures.capturedAt')"
                data-index="capturedAt"
                :width="168"
              >
                <template #cell="{ record }">
                  {{ formatTime(record.capturedAt) }}
                </template>
              </a-table-column>
              <a-table-column :title="t('admin.developerWorkbench.captures.redactedEntry')">
                <template #cell="{ record }">
                  {{ captureDetail(capture.key, record) }}
                  <a-typography-text v-if="record.sizeBytes !== undefined" type="secondary">
                    · {{ formatBytes(record.sizeBytes) }}
                  </a-typography-text>
                </template>
              </a-table-column>
            </template>
            <template #empty>
              <a-empty :description="t('admin.developerWorkbench.captures.empty')" />
            </template>
          </a-table>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card :title="t('admin.developerWorkbench.minecraft.title')">
      <a-alert
        v-if="!minecraft.available"
        type="warning"
        show-icon
        :title="t('admin.developerWorkbench.minecraft.unavailable')"
        class="mb-3"
      />
      <a-grid :cols="{ xs: 2, sm: 3, lg: 5 }" :col-gap="16" :row-gap="16" class="mb-3">
        <a-grid-item>
          <a-statistic :title="t('admin.developerWorkbench.minecraft.total')" :value="minecraft.total" />
        </a-grid-item>
        <a-grid-item>
          <a-statistic :title="t('admin.developerWorkbench.minecraft.pending')" :value="minecraft.pending" />
        </a-grid-item>
        <a-grid-item>
          <a-statistic :title="t('admin.developerWorkbench.minecraft.claimed')" :value="minecraft.claimed" />
        </a-grid-item>
        <a-grid-item>
          <a-statistic :title="t('admin.developerWorkbench.minecraft.completed')" :value="minecraft.completed" />
        </a-grid-item>
        <a-grid-item>
          <a-statistic :title="t('admin.developerWorkbench.minecraft.failed')" :value="minecraft.failed" />
        </a-grid-item>
      </a-grid>

      <a-table :data="minecraft.recent" :pagination="false" row-key="createdAt">
        <template #columns>
          <a-table-column
            :title="t('admin.developerWorkbench.minecraft.taskType')"
            data-index="taskType"
          >
            <template #cell="{ record }">
              {{ t(`admin.developerWorkbench.minecraft.taskTypes.${record.taskType}`, record.taskType) }}
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.developerWorkbench.minecraft.status')"
            data-index="status"
            :width="120"
          >
            <template #cell="{ record }">
              <a-tag :color="statusColor(record.status)">
                {{ t(`admin.developerWorkbench.minecraft.statuses.${record.status}`, record.status) }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.developerWorkbench.minecraft.createdAt')"
            data-index="createdAt"
            :width="190"
          >
            <template #cell="{ record }">
              {{ formatTime(record.createdAt) }}
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.developerWorkbench.minecraft.completedAt')"
            data-index="completedAt"
            :width="190"
          >
            <template #cell="{ record }">
              {{ formatTime(record.completedAt) }}
            </template>
          </a-table-column>
        </template>
        <template #empty>
          <a-empty :description="t('admin.developerWorkbench.minecraft.empty')" />
        </template>
      </a-table>
    </a-card>
  </section>
</template>
