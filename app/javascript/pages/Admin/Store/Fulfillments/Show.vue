<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

defineProps<{
  fulfillment: {
    id: number
    delivery_id: string
    status: string
    order_number: string
    product_name: string
    attempts_count: number
    last_error: string | null
    target_server?: string | null
    target_server_process_state?: string | null
    target_server_url?: string | null
  }
}>()

function statusColor(status: string) {
  if (status === 'completed' || status === 'fulfilled' || status === 'success') return 'green'
  if (status === 'pending' || status === 'processing') return 'orange'
  if (status === 'failed') return 'red'
  return 'gray'
}
</script>

<template>
  <section class="admin-store-fulfillment">
    <a-page-header
      :title="t('admin.fulfillments.title', { id: fulfillment.delivery_id })"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-card class="mb-6 max-w-3xl" :bordered="true">
      <a-descriptions :column="1" bordered>
        <a-descriptions-item :label="t('admin.common.status')">
          <a-tag :color="statusColor(fulfillment.status)">
            {{ fulfillment.status }}
          </a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.common.order')">
          {{ fulfillment.order_number }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.common.product')">
          {{ fulfillment.product_name }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.fulfillments.attempts')">
          {{ fulfillment.attempts_count }}
        </a-descriptions-item>
        <a-descriptions-item
          v-if="fulfillment.target_server"
          :label="t('admin.fulfillments.targetServer')"
        >
          <Link
            v-if="fulfillment.target_server_url"
            :href="fulfillment.target_server_url"
            class="arco-link no-underline"
          >
            {{ fulfillment.target_server }} ({{ fulfillment.target_server_process_state }})
          </Link>
          <span v-else>{{ fulfillment.target_server }}</span>
        </a-descriptions-item>
      </a-descriptions>

      <a-alert
        v-if="fulfillment.last_error"
        type="error"
        :title="fulfillment.last_error"
        show-icon
        class="mt-4"
      />
    </a-card>

    <a-space wrap>
      <Link
        v-if="fulfillment.status === 'pending' || fulfillment.status === 'failed'"
        :href="adminRoutes.storeFulfillment(fulfillment.id)"
        method="patch"
        as="button"
        :data="{ retry: '1' }"
        class="arco-btn arco-btn-primary arco-btn-size-medium"
      >
        {{ t('admin.fulfillments.retry') }}
      </Link>
      <Link
        :href="adminRoutes.storeFulfillments"
        class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
      >
        {{ t('admin.ui.back') }}
      </Link>
    </a-space>
  </section>
</template>
