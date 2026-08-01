<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type AuditDetail = {
  id: number
  actionLabel: string
  actionCode: string
  actor: { username: string; publicId: string } | null
  resource: {
    type: string | null
    typeLabel: string
    id: number | null
    publicId: string | null
  }
  requestId: string | null
  reason: string | null
  occurredAt: string
  occurredAtIso: string
  ipAddress: string | null
  userAgent: string | null
  beforeState: Record<string, unknown>
  afterState: Record<string, unknown>
  metadata: Record<string, unknown>
}

const props = defineProps<{
  log: AuditDetail
  backUrl: string
}>()

const { t } = useI18n()

function pretty(value: Record<string, unknown>) {
  return JSON.stringify(value, null, 2)
}

const hasBeforeState = computed(() => Object.keys(props.log.beforeState).length > 0)
const hasAfterState = computed(() => Object.keys(props.log.afterState).length > 0)
const hasMetadata = computed(() => Object.keys(props.log.metadata).length > 0)
</script>

<template>
  <a-space direction="vertical" :size="16" fill>
    <a-page-header
      :title="log.actionLabel"
      :subtitle="t('admin.audit.detailSubtitle')"
      :show-back="false"
    >
      <template #extra>
        <Link :href="backUrl">
          <a-button shape="round">{{ t('admin.audit.back') }}</a-button>
        </Link>
      </template>
    </a-page-header>

    <a-alert
      type="info"
      show-icon
      :closable="false"
      :title="t('admin.audit.immutableNotice')"
    />

    <a-card :bordered="false">
      <a-descriptions
        :column="{ xs: 1, sm: 2, lg: 3 }"
        bordered
        size="large"
      >
        <a-descriptions-item :label="t('admin.audit.action')">
          <a-space direction="vertical" :size="2">
            <a-typography-text bold>{{ log.actionLabel }}</a-typography-text>
            <a-typography-text code copyable>{{ log.actionCode }}</a-typography-text>
          </a-space>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.actor')">
          <a-space v-if="log.actor" direction="vertical" :size="2">
            <a-typography-text>{{ log.actor.username }}</a-typography-text>
            <a-typography-text type="secondary">{{ log.actor.publicId }}</a-typography-text>
          </a-space>
          <a-typography-text v-else type="secondary">{{ t('admin.audit.systemActor') }}</a-typography-text>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.occurredAt')">
          <time :datetime="log.occurredAtIso">{{ log.occurredAt }}</time>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.resource')">
          <a-space direction="vertical" :size="2">
            <a-typography-text>{{ log.resource.typeLabel }}</a-typography-text>
            <a-typography-text type="secondary">
              {{ log.resource.publicId || log.resource.id || t('admin.audit.notAvailable') }}
            </a-typography-text>
          </a-space>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.requestId')">
          <a-tag v-if="log.requestId" color="arcoblue" bordered>{{ log.requestId }}</a-tag>
          <a-typography-text v-else type="secondary">{{ t('admin.audit.notAvailable') }}</a-typography-text>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.ipAddress')">
          <a-typography-text>{{ log.ipAddress || t('admin.audit.notAvailable') }}</a-typography-text>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.reason')" :span="3">
          <a-typography-paragraph>
            {{ log.reason || t('admin.audit.notAvailable') }}
          </a-typography-paragraph>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.audit.userAgent')" :span="3">
          <a-typography-paragraph copyable :ellipsis="{ rows: 2, expandable: true }">
            {{ log.userAgent || t('admin.audit.notAvailable') }}
          </a-typography-paragraph>
        </a-descriptions-item>
      </a-descriptions>
    </a-card>

    <a-grid :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
      <a-grid-item>
        <a-card :bordered="false" :title="t('admin.audit.beforeState')">
          <a-textarea
            v-if="hasBeforeState"
            :model-value="pretty(log.beforeState)"
            readonly
            :auto-size="{ minRows: 8, maxRows: 20 }"
            :aria-label="t('admin.audit.beforeState')"
          />
          <a-empty v-else :description="t('admin.audit.noState')" />
        </a-card>
      </a-grid-item>
      <a-grid-item>
        <a-card :bordered="false" :title="t('admin.audit.afterState')">
          <a-textarea
            v-if="hasAfterState"
            :model-value="pretty(log.afterState)"
            readonly
            :auto-size="{ minRows: 8, maxRows: 20 }"
            :aria-label="t('admin.audit.afterState')"
          />
          <a-empty v-else :description="t('admin.audit.noState')" />
        </a-card>
      </a-grid-item>
      <a-grid-item :span="{ xs: 1, lg: 2 }">
        <a-card :bordered="false" :title="t('admin.audit.context')">
          <a-textarea
            v-if="hasMetadata"
            :model-value="pretty(log.metadata)"
            readonly
            :auto-size="{ minRows: 8, maxRows: 24 }"
            :aria-label="t('admin.audit.context')"
          />
          <a-empty v-else :description="t('admin.audit.noContext')" />
        </a-card>
      </a-grid-item>
    </a-grid>
  </a-space>
</template>
