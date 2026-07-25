<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
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
</script>

<template>
  <section class="admin-system-webhook-subscriptions">
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
      class="mb-4 !px-0"
    >
      <template #extra>
        <Link
          :href="newUrl"
          class="arco-btn arco-btn-primary arco-btn-size-medium no-underline"
        >
          {{ t('admin.webhookSubscriptions.new') }}
        </Link>
      </template>
    </a-page-header>

    <a-card :bordered="true" :body-style="{ padding: 0 }">
      <a-table
        :data="subscriptions"
        row-key="id"
        :pagination="false"
        :bordered="{ cell: true }"
        :scroll="{ x: 1120 }"
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
              <a-tooltip :content="record.url">
                <a-typography-text ellipsis class="block max-w-[270px]">
                  {{ record.url }}
                </a-typography-text>
              </a-tooltip>
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
              <Link
                :href="record.editUrl"
                class="arco-btn arco-btn-outline arco-btn-size-small no-underline"
              >
                {{ t('admin.ui.edit') }}
              </Link>
            </template>
          </a-table-column>
        </template>

        <template #empty>
          <a-empty :description="t('admin.webhookSubscriptions.empty')" />
        </template>
      </a-table>
    </a-card>
  </section>
</template>
