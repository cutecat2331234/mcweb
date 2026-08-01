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
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
    >
      <template #extra>
        <a-button type="primary" :href="newUrl">
          {{ t('admin.apiKeys.new') }}
        </a-button>
      </template>
    </a-page-header>

    <a-grid :cols="24" :col-gap="16" :row-gap="16">
      <a-grid-item v-if="keys.length === 0" :span="{ xs: 24, md: 0 }">
        <a-card :bordered="true">
          <a-empty :description="t('admin.apiKeys.empty')" />
        </a-card>
      </a-grid-item>

      <a-grid-item
        v-for="key in keys"
        :key="`mobile-${key.id}`"
        :span="{ xs: 24, sm: 12, md: 0 }"
      >
        <a-card :title="key.name" :bordered="true" hoverable>
          <template #extra>
            <a-tag :color="key.revoked ? 'gray' : 'green'">
              {{ key.revoked ? t('admin.apiKeys.revoked') : t('admin.apiKeys.active') }}
            </a-tag>
          </template>

          <a-descriptions
            :column="1"
            layout="inline-horizontal"
            size="small"
            table-layout="fixed"
          >
            <a-descriptions-item :label="t('admin.apiKeys.prefix')">
              <a-typography-text code>{{ key.prefix }}…</a-typography-text>
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.apiKeys.scopes')">
              <a-space wrap :size="[4, 4]">
                <a-tag v-for="scope in key.scopes" :key="scope" color="arcoblue">
                  {{ scope }}
                </a-tag>
              </a-space>
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.apiKeys.user')">
              {{ key.user || '—' }}
            </a-descriptions-item>
            <a-descriptions-item :label="t('admin.apiKeys.lastUsed')">
              {{ key.lastUsedAt || '—' }}
            </a-descriptions-item>
          </a-descriptions>

          <template v-if="!key.revoked">
            <a-divider />
            <a-button
              type="primary"
              status="danger"
              size="small"
              @click="revoke(key)"
            >
              {{ t('admin.apiKeys.revoke') }}
            </a-button>
          </template>
        </a-card>
      </a-grid-item>

      <a-grid-item :span="{ xs: 0, md: 24 }">
        <a-card :bordered="true" :body-style="{ padding: 0 }">
          <a-table
            :data="keys"
            row-key="id"
            :pagination="false"
            :bordered="{ cell: true }"
            :scroll="{ minWidth: 1080 }"
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
      </a-grid-item>
    </a-grid>
  </a-space>
</template>
