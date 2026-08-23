<script setup lang="ts">
import { computed, ref } from 'vue'
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import { Modal } from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'
import AdminAlertBanners, { type AdminAlert } from '@/components/admin/AdminAlertBanners.vue'
import NodeTasksTable, { type NodeTaskRow } from '@/components/admin/NodeTasksTable.vue'
import MetricHistoryPanel, { type MetricPoint } from '@/components/admin/MetricHistoryPanel.vue'
import WorldRestoreLifecycle from '@/components/admin/minecraft/WorldRestoreLifecycle.vue'
import type { WorldSafetyProps } from '@/components/admin/minecraft/worldRestoreTypes'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

interface ProcessMismatchAlert {
  at?: string
  connector_online?: boolean
  process_state?: string
}

interface PageAction {
  label: string
  href: string
  method?: string
  confirm?: string
}

const props = defineProps<{
  title: string
  server: Record<string, unknown> & {
    node_managed?: boolean
    node_id?: string
    node_url?: string | null
    plugin_config?: { website_url: string; server_id: string; connector_secret: string }
  }
  processMismatchAlert?: ProcessMismatchAlert | null
  metricHistory?: MetricPoint[]
  nodeTasks: NodeTaskRow[]
  defaultLogPath: string
  controlUrls: Record<string, string>
  worldSafety: WorldSafetyProps
  backUrl: string
  actions: PageAction[]
  connectorSecretOnce?: string | null
}>()

const { t } = useI18n()
const command = ref('')
const consoleCommand = ref('')
const logPath = ref(props.defaultLogPath)

const serverFields = computed(() => [
  { key: 'public_id', label: t('adminMinecraft.fieldServerId') },
  { key: 'name', label: t('adminMinecraft.colName') },
  { key: 'address', label: t('adminMinecraft.colAddress') },
  { key: 'port', label: t('adminMinecraft.colPort') },
  { key: 'status', label: t('adminMinecraft.colStatus') },
  { key: 'process_state', label: t('adminMinecraft.colProcessState') },
  { key: 'connection_mode', label: t('adminMinecraft.connectionMode') },
  { key: 'node_name', label: t('adminMinecraft.node') },
  { key: 'working_directory', label: t('adminMinecraft.workingDirectory') },
  { key: 'last_heartbeat', label: t('adminMinecraft.fieldLastHeartbeat') },
  { key: 'online_players', label: t('adminMinecraft.fieldOnlinePlayers') },
  { key: 'tps', label: t('adminMinecraft.fieldTps') },
  { key: 'version', label: t('adminMinecraft.fieldVersion') },
  { key: 'secret_fingerprint', label: t('adminMinecraft.fieldSecretFingerprint') },
])

const alerts = computed<AdminAlert[]>(() => {
  const list: AdminAlert[] = []
  const alert = props.processMismatchAlert
  if (alert) {
    list.push({
      level: 'warning',
      message: t('adminMinecraft.processMismatchAlert', {
        processState: alert.process_state || '—',
        connectorOnline: alert.connector_online
          ? t('adminMinecraft.yes')
          : t('adminMinecraft.no'),
      }),
    })
  }
  return list
})

function runCommand() {
  if (!props.controlUrls.exec || !command.value.trim()) return
  router.post(props.controlUrls.exec, { command: command.value.trim() })
}

function runConsoleCommand() {
  if (!props.controlUrls.console || !consoleCommand.value.trim()) return
  router.post(props.controlUrls.console, { command: consoleCommand.value.trim() })
}

function confirmOperation(title: string, content: string, operation: () => void, danger = false) {
  Modal.warning({
    title,
    content,
    okText: title,
    cancelText: t('common.cancel'),
    hideCancel: false,
    okButtonProps: danger ? { status: 'danger' } : undefined,
    onOk: operation,
  })
}

function tailLogs() {
  if (!props.controlUrls.tail_logs) return
  router.post(props.controlUrls.tail_logs, { path: logPath.value })
}

function runPageAction(action: PageAction) {
  const perform = () => {
    if (action.method === 'post') router.post(action.href)
    else if (action.method === 'delete') router.delete(action.href)
    else router.visit(action.href)
  }

  if (action.confirm) {
    confirmOperation(action.label, action.confirm, perform, action.method === 'delete')
  } else {
    perform()
  }
}
</script>

<template>
  <a-page-header :title="title" :show-back="false">
    <template #extra>
      <a-space wrap>
        <a-button @click="router.visit(adminRoutes.minecraftPlayers)">
          {{ t('adminMinecraft.players') }}
        </a-button>
        <a-button @click="router.visit(backUrl)">
          {{ t('adminMinecraft.backToServers') }}
        </a-button>
      </a-space>
    </template>
  </a-page-header>

  <AdminAlertBanners :alerts="alerts" />

  <a-alert
    v-if="connectorSecretOnce"
    type="warning"
    show-icon
    class="mb-4 admin-secret-alert"
  >
    <template #title>{{ t('adminMinecraft.newConnectorSecret') }}</template>
    <pre class="admin-code-block">{{ connectorSecretOnce }}</pre>
  </a-alert>

  <a-card :bordered="true">
    <a-descriptions :column="{ xs: 1, md: 2 }" bordered>
      <a-descriptions-item v-for="field in serverFields" :key="field.key" :label="field.label">
        <a-link
          v-if="field.key === 'node_name' && server.node_url"
          @click="router.visit(String(server.node_url))"
        >
          {{ server.node_name }}
        </a-link>
        <span v-else class="break-all">{{ server[field.key] ?? '—' }}</span>
      </a-descriptions-item>
    </a-descriptions>
  </a-card>

  <a-card
    v-if="server.plugin_config"
    :title="t('adminMinecraft.pluginConfig')"
    :bordered="true"
    class="mt-4"
  >
    <pre class="admin-code-block">website-url: "{{ server.plugin_config.website_url }}"
server-id: "{{ server.plugin_config.server_id }}"
connector-secret: "{{ server.plugin_config.connector_secret }}"</pre>
  </a-card>

  <a-card
    v-if="server.node_managed"
    :title="t('adminMinecraft.actions')"
    :bordered="true"
    class="mt-4"
  >
    <a-space wrap>
      <a-button
        v-if="controlUrls.start"
        type="primary"
        status="success"
        :disabled="worldSafety.start_blocked"
        @click="router.post(controlUrls.start)"
      >
        {{ t('adminMinecraft.startServer') }}
      </a-button>
      <a-button v-if="controlUrls.stop" @click="router.post(controlUrls.stop)">
        {{ t('adminMinecraft.stopServer') }}
      </a-button>
      <a-button
        v-if="controlUrls.restart"
        status="warning"
        :disabled="worldSafety.start_blocked"
        @click="router.post(controlUrls.restart)"
      >
        {{ t('adminMinecraft.restartServer') }}
      </a-button>
    </a-space>
  </a-card>

  <WorldRestoreLifecycle :model="worldSafety" />

  <a-grid :cols="{ xs: 1, sm: 1, lg: 2 }" :col-gap="16" :row-gap="16" class="mt-4">
    <a-grid-item v-if="controlUrls.exec">
      <a-card :title="t('adminMinecraft.remoteCommand')" :bordered="true">
        <a-input-search
          v-model="command"
          :button-text="t('adminMinecraft.runCommand')"
          :placeholder="t('adminMinecraft.remoteCommandPlaceholder')"
          search-button
          @search="runCommand"
        />
      </a-card>
    </a-grid-item>
    <a-grid-item v-if="controlUrls.console">
      <a-card :title="t('adminMinecraft.consoleCommand')" :bordered="true">
        <a-input-search
          v-model="consoleCommand"
          :button-text="t('adminMinecraft.runCommand')"
          :placeholder="t('adminMinecraft.consoleCommandPlaceholder')"
          search-button
          @search="runConsoleCommand"
        />
      </a-card>
    </a-grid-item>
    <a-grid-item v-if="controlUrls.tail_logs">
      <a-card :title="t('adminMinecraft.tailLogs')" :bordered="true">
        <a-input-search
          v-model="logPath"
          :button-text="t('adminMinecraft.tailLogsRun')"
          :placeholder="t('adminMinecraft.tailLogsPlaceholder')"
          search-button
          @search="tailLogs"
        />
      </a-card>
    </a-grid-item>
  </a-grid>

  <MetricHistoryPanel
    v-if="metricHistory"
    class="mt-8"
    :points="metricHistory"
    :title="t('adminMinecraft.metricHistory')"
  />
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
