<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface ApiKey {
  id: number
  name: string
  prefix: string
  scopes: string[]
  user: string | null
  lastUsedAt: string | null
  revoked: boolean
  createdAt: string
  revokeUrl: string
}

defineProps<{
  title: string
  subtitle?: string
  newUrl: string
  keys: ApiKey[]
}>()

async function revoke(key: ApiKey) {
  const ok = await confirm({
    title: t('admin.apiKeys.revokeTitle'),
    message: t('admin.apiKeys.revokeConfirm', { name: key.name }),
    confirmLabel: t('admin.apiKeys.revoke'),
    variant: 'destructive',
  })
  if (!ok) return
  router.post(key.revokeUrl)
}
</script>

<template>
  <section class="admin-system-api-keys">
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
          {{ t('admin.apiKeys.new') }}
        </Link>
      </template>
    </a-page-header>

    <a-card :bordered="true" :body-style="{ padding: 0 }">
      <a-table
        :data="keys"
        row-key="id"
        :pagination="false"
        :bordered="{ cell: true }"
        :scroll="{ x: 1080 }"
        stripe
      >
        <template #columns>
          <a-table-column :title="t('admin.apiKeys.name')" data-index="name" :width="180" />
          <a-table-column :title="t('admin.apiKeys.prefix')" :width="150">
            <template #cell="{ record }">
              <a-typography-text code>{{ record.prefix }}…</a-typography-text>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.apiKeys.scopes')" :width="180">
            <template #cell="{ record }">
              <a-space wrap :size="[4, 4]">
                <a-tag v-for="scope in record.scopes" :key="scope" color="arcoblue">
                  {{ scope }}
                </a-tag>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.apiKeys.user')" data-index="user" :width="180">
            <template #cell="{ record }">
              {{ record.user || '—' }}
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.apiKeys.lastUsed')" data-index="lastUsedAt" :width="180">
            <template #cell="{ record }">
              {{ record.lastUsedAt || '—' }}
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.apiKeys.status')" :width="120">
            <template #cell="{ record }">
              <a-tag :color="record.revoked ? 'gray' : 'green'">
                {{ record.revoked ? t('admin.apiKeys.revoked') : t('admin.apiKeys.active') }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.ui.actions')" :width="120" fixed="right">
            <template #cell="{ record }">
              <a-button
                v-if="!record.revoked"
                type="primary"
                status="danger"
                size="small"
                @click="revoke(record)"
              >
                {{ t('admin.apiKeys.revoke') }}
              </a-button>
            </template>
          </a-table-column>
        </template>

        <template #empty>
          <a-empty :description="t('admin.apiKeys.empty')" />
        </template>
      </a-table>
    </a-card>
  </section>
</template>
