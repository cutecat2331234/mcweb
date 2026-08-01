<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface Subscription {
  id: number
  name: string
  url: string
  event: string
  active: boolean
  lastStatus: string | null
  lastDeliveredAt: string | null
  failureCount: number
  editUrl: string
}

defineProps<{
  title: string
  subtitle?: string
  newUrl: string
  subscriptions: Subscription[]
}>()

function deliveryStatusColor(status: string | null) {
  if (!status) return 'gray'
  const normalized = status.toLowerCase()
  if (normalized.includes('success') || normalized.includes('ok') || normalized.startsWith('2')) {
    return 'green'
  }
  if (normalized.includes('pending')) return 'orange'
  return 'red'
}

function visit(url: string) {
  router.visit(url, { preserveScroll: true })
}
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
    >
      <template #extra>
        <a-button type="primary" @click="visit(newUrl)">
          {{ t('admin.webhookSubscriptions.new') }}
        </a-button>
      </template>
    </a-page-header>

    <a-grid :cols="24" :col-gap="16" :row-gap="16">
      <a-grid-item v-if="subscriptions.length === 0" :span="{ xs: 24, md: 0 }">
        <a-card :bordered="true">
          <a-empty :description="t('admin.webhookSubscriptions.empty')" />
        </a-card>
      </a-grid-item>

      <a-grid-item
        v-for="subscription in subscriptions"
        :key="`mobile-${subscription.id}`"
        :span="{ xs: 24, sm: 12, md: 0 }"
      >
        <a-card :title="subscription.name" :bordered="true" hoverable>
          <template #extra>
            <a-tag :color="subscription.active ? 'green' : 'gray'">
              {{
                subscription.active
                  ? t('admin.webhookSubscriptions.active')
                  : t('admin.webhookSubscriptions.disabled')
              }}
            </a-tag>
          </template>

          <a-descriptions
            :column="1"
            layout="inline-horizontal"
            size="small"
            table-layout="fixed"
          >
            <a-descriptions-item :label="t('admin.webhookSubscriptions.event')">
              <a-typography-text code>{{ subscription.event }}</a-typography-text>
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.webhookSubscriptions.url')">
              <a-typography-paragraph :ellipsis="{ rows: 2, showTooltip: true }">
                {{ subscription.url }}
              </a-typography-paragraph>
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.webhookSubscriptions.status')">
              <a-space wrap :size="[4, 4]">
                <a-tag
                  v-if="subscription.lastStatus"
                  :color="deliveryStatusColor(subscription.lastStatus)"
                >
                  {{ subscription.lastStatus }}
                </a-tag>
                <a-tag v-if="subscription.failureCount > 0" color="red">
                  {{ subscription.failureCount }}
                </a-tag>
                <a-typography-text
                  v-if="!subscription.lastStatus && subscription.failureCount === 0"
                  type="secondary"
                >
                  —
                </a-typography-text>
              </a-space>
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.webhookSubscriptions.lastDelivered')">
              {{ subscription.lastDeliveredAt || '—' }}
            </a-descriptions-item>
          </a-descriptions>

          <a-divider />
          <a-button size="small" @click="visit(subscription.editUrl)">
            {{ t('admin.ui.edit') }}
          </a-button>
        </a-card>
      </a-grid-item>

      <a-grid-item :span="{ xs: 0, md: 24 }">
        <a-card :bordered="true">
          <a-table
            :data="subscriptions"
            row-key="id"
            :pagination="false"
            :bordered="{ cell: true }"
            :scroll="{ minWidth: 1120 }"
            stripe
          >
            <template #columns>
              <a-table-column :title="t('admin.webhookSubscriptions.name')" data-index="name" :width="180" />
              <a-table-column :title="t('admin.webhookSubscriptions.event')" :width="180">
                <template #cell="{ record }">
                  <a-typography-text code>{{ record.event }}</a-typography-text>
                </template>
              </a-table-column>
              <a-table-column :title="t('admin.webhookSubscriptions.url')" :width="300">
                <template #cell="{ record }">
                  <a-typography-paragraph :ellipsis="{ rows: 1, showTooltip: true }">
                    {{ record.url }}
                  </a-typography-paragraph>
                </template>
              </a-table-column>
              <a-table-column :title="t('admin.webhookSubscriptions.status')" :width="240">
                <template #cell="{ record }">
                  <a-space wrap :size="[4, 4]">
                    <a-tag :color="record.active ? 'green' : 'gray'">
                      {{
                        record.active
                          ? t('admin.webhookSubscriptions.active')
                          : t('admin.webhookSubscriptions.disabled')
                      }}
                    </a-tag>
                    <a-tag v-if="record.lastStatus" :color="deliveryStatusColor(record.lastStatus)">
                      {{ record.lastStatus }}
                    </a-tag>
                    <a-tag v-if="record.failureCount > 0" color="red">
                      {{ record.failureCount }}
                    </a-tag>
                  </a-space>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.webhookSubscriptions.lastDelivered')"
                data-index="lastDeliveredAt"
                :width="190"
              >
                <template #cell="{ record }">
                  {{ record.lastDeliveredAt || '—' }}
                </template>
              </a-table-column>
              <a-table-column :title="t('admin.ui.actions')" :width="110" fixed="right">
                <template #cell="{ record }">
                  <a-button size="small" @click="visit(record.editUrl)">
                    {{ t('admin.ui.edit') }}
                  </a-button>
                </template>
              </a-table-column>
            </template>

            <template #empty>
              <a-empty :description="t('admin.webhookSubscriptions.empty')" />
            </template>
          </a-table>
        </a-card>
      </a-grid-item>
    </a-grid>
  </a-space>
</template>
