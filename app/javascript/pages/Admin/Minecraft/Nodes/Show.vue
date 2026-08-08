<script setup lang="ts">
import { computed } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import AdminAlertBanners, { type AdminAlert } from '@/components/admin/AdminAlertBanners.vue'
import NodeTasksTable, { type NodeTaskRow } from '@/components/admin/NodeTasksTable.vue'
import MetricHistoryPanel, { type MetricPoint } from '@/components/admin/MetricHistoryPanel.vue'

defineOptions({ layout: AdminLayout })

interface ConnectorProxyEntry {
  last_request_at?: string
  last_success_at?: string
  last_error?: string
}

interface PageAction {
  label: string
  href: string
  method?: string
  confirm?: string
}

const props = defineProps<{
  title: string
  node: {
    public_id: string
    name: string
    hostname: string
    status: string
    secret_fingerprint: string
    last_heartbeat_at: string
    proxy_listen_url: string
  }
  connectorProxy?: Record<string, ConnectorProxyEntry> | null
  hostMetrics?: Record<string, unknown> | null
  metricHistory?: MetricPoint[]
  nodeTasks: NodeTaskRow[]
  alerts: AdminAlert[]
  servers: Array<{ name: string; public_id: string; process_state: string; url: string }>
  backUrl: string
  actions: PageAction[]
  nodeSecretOnce?: string | null
  pairingTokenOnce?: string | null
  pairingTokenExpiresAt?: string | null
}>()

const { t } = useI18n()

const nodeFields = computed(() => [
  { key: 'public_id', label: t('adminMinecraft.fieldNodeId') },
  { key: 'name', label: t('adminMinecraft.colName') },
  { key: 'hostname', label: t('adminMinecraft.colHostname') },
  { key: 'status', label: t('adminMinecraft.colStatus') },
  { key: 'proxy_listen_url', label: t('adminMinecraft.proxyListenUrl') },
  { key: 'last_heartbeat_at', label: t('adminMinecraft.fieldLastHeartbeat') },
  { key: 'secret_fingerprint', label: t('adminMinecraft.fieldSecretFingerprint') },
])

const connectorProxyRows = computed(() => {
  const proxy = props.connectorProxy
  if (!proxy || typeof proxy !== 'object') return []
  return Object.entries(proxy).map(([serverId, stats]) => ({
    serverId,
    lastRequestAt: stats.last_request_at || '—',
    lastSuccessAt: stats.last_success_at || '—',
    lastError: stats.last_error || '—',
  }))
})

const hostMetricRows = computed(() => {
  const metrics = props.hostMetrics
  if (!metrics || typeof metrics !== 'object') return []
  return Object.entries(metrics).map(([key, value]) => ({
    key,
    value: value == null ? '—' : String(value),
  }))
})

const connectorColumns = computed(() => [
  { title: t('adminMinecraft.fieldServerId'), dataIndex: 'serverId', width: 180 },
  { title: t('adminMinecraft.lastRequestAt'), dataIndex: 'lastRequestAt', width: 180 },
  { title: t('adminMinecraft.lastSuccessAt'), dataIndex: 'lastSuccessAt', width: 180 },
  { title: t('adminMinecraft.lastError'), dataIndex: 'lastError' },
])

function runPageAction(action: PageAction) {
  const perform = () => {
    if (action.method === 'post') router.post(action.href)
    else if (action.method === 'delete') router.delete(action.href)
    else router.visit(action.href)
  }

  if (!action.confirm) {
    perform()
    return
  }

  Modal.warning({
    title: action.label,
    content: action.confirm,
    okText: action.label,
    cancelText: t('common.cancel'),
    hideCancel: false,
    okButtonProps: action.method === 'delete' ? { status: 'danger' } : undefined,
    onOk: perform,
  })
}
</script>

<template>
  <a-page-header :title="title" :show-back="false">
    <template #extra>
      <a-button @click="router.visit(backUrl)">{{ t('adminMinecraft.backToNodes') }}</a-button>
    </template>
  </a-page-header>

  <AdminAlertBanners :alerts="alerts" />

  <a-space
    v-if="nodeSecretOnce || pairingTokenOnce"
    direction="vertical"
    fill
    class="mb-4 admin-secret-alert"
  >
    <a-alert v-if="nodeSecretOnce" type="warning" show-icon>
      <template #title>{{ t('adminMinecraft.newNodeSecret') }}</template>
      <pre class="admin-code-block">{{ nodeSecretOnce }}</pre>
    </a-alert>
    <a-alert v-if="pairingTokenOnce" type="warning" show-icon>
      <template #title>
        {{ t('adminMinecraft.newPairingToken') }}
        <span v-if="pairingTokenExpiresAt">({{ pairingTokenExpiresAt }})</span>
      </template>
      <pre class="admin-code-block">{{ pairingTokenOnce }}</pre>
    </a-alert>
  </a-space>

  <a-card :bordered="true">
    <a-descriptions :column="{ xs: 1, md: 2 }" bordered>
      <a-descriptions-item v-for="field in nodeFields" :key="field.key" :label="field.label">
        <span class="break-all">{{ node[field.key as keyof typeof node] || '—' }}</span>
      </a-descriptions-item>
    </a-descriptions>
  </a-card>

  <a-grid :cols="{ xs: 1, sm: 1, lg: 2 }" :col-gap="16" :row-gap="16" class="mt-4">
    <a-grid-item v-if="hostMetricRows.length">
      <a-card :title="t('adminMinecraft.hostMetrics')" :bordered="true">
        <a-descriptions :column="1" bordered size="small">
          <a-descriptions-item v-for="row in hostMetricRows" :key="row.key" :label="row.key">
            <span class="break-all">{{ row.value }}</span>
          </a-descriptions-item>
        </a-descriptions>
      </a-card>
    </a-grid-item>
    <a-grid-item v-if="servers.length">
      <a-card :title="t('adminMinecraft.managedServers')" :bordered="true">
        <a-list :bordered="false">
          <a-list-item v-for="server in servers" :key="server.public_id">
            <a-link @click="router.visit(server.url)">{{ server.name }}</a-link>
            <template #extra>
              <a-tag>{{ server.process_state }}</a-tag>
            </template>
          </a-list-item>
        </a-list>
      </a-card>
    </a-grid-item>
  </a-grid>

  <MetricHistoryPanel
    v-if="metricHistory"
    class="mt-8"
    :points="metricHistory"
    :title="t('adminMinecraft.metricHistory')"
  />

  <a-card
    v-if="connectorProxyRows.length"
    :title="t('adminMinecraft.connectorProxy')"
    :bordered="true"
    class="mt-8"
  >
    <a-table
      :columns="connectorColumns"
      :data="connectorProxyRows"
      row-key="serverId"
      :pagination="false"
      :scroll="{ x: 760 }"
    />
  </a-card>

  <NodeTasksTable :tasks="nodeTasks" />

  <a-card v-if="actions.length" :title="t('adminMinecraft.actions')" :bordered="true" class="mt-4">
    <a-space wrap>
      <a-button
        v-for="action in actions"
        :key="action.href"
        :status="action.method === 'delete' ? 'danger' : undefined"
        @click="runPageAction(action)"
      >
        {{ action.label }}
      </a-button>
    </a-space>
  </a-card>
</template>

<style scoped>
.admin-secret-alert {
  max-width: 880px;
}
.admin-code-block {
  max-width: 100%;
  margin: 0;
  padding: 12px;
  overflow: auto;
  color: var(--color-text-1);
  background: var(--color-fill-2);
  border-radius: 4px;
  white-space: pre-wrap;
  word-break: break-all;
}
.break-all {
  word-break: break-all;
}
</style>
