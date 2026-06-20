<script setup lang="ts">
import { computed, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import AdminAlertBanners, { type AdminAlert } from '@/components/admin/AdminAlertBanners.vue'
import NodeTasksTable, { type NodeTaskRow } from '@/components/admin/NodeTasksTable.vue'
import MetricHistoryPanel, { type MetricPoint } from '@/components/admin/MetricHistoryPanel.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

interface ProcessMismatchAlert {
  at?: string
  connector_online?: boolean
  process_state?: string
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
  backUrl: string
  actions: Array<{ label: string; href: string; method?: string; confirm?: string }>
  connectorSecretOnce?: string | null
}>()

const { t } = useI18n()
const command = ref('')
const consoleCommand = ref('')
const restoreArchive = ref('')
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
        connectorOnline: alert.connector_online ? t('adminMinecraft.yes') : t('adminMinecraft.no'),
      }),
    })
  }
  return list
})

function runCommand() {
  if (!props.controlUrls.exec || !command.value.trim()) return
  router.post(props.controlUrls.exec, { command: command.value })
}

function runConsoleCommand() {
  if (!props.controlUrls.console || !consoleCommand.value.trim()) return
  router.post(props.controlUrls.console, { command: consoleCommand.value })
}

function backupWorld() {
  if (!props.controlUrls.backup) return
  if (!window.confirm(t('adminMinecraft.confirmBackup'))) return
  router.post(props.controlUrls.backup)
}

function restoreWorld() {
  if (!props.controlUrls.restore || !restoreArchive.value.trim()) return
  if (!window.confirm(t('adminMinecraft.confirmRestore'))) return
  router.post(props.controlUrls.restore, { archive: restoreArchive.value })
}

function tailLogs() {
  if (!props.controlUrls.tail_logs) return
  router.post(props.controlUrls.tail_logs, { path: logPath.value })
}
</script>

<template>
  <PageHeader :title="title" />

  <AdminAlertBanners :alerts="alerts" />

  <section
    v-if="connectorSecretOnce"
    class="mb-4 max-w-2xl rounded border border-amber-500/40 bg-amber-500/10 p-4 text-sm"
  >
    <p class="mb-2 font-medium">{{ t('adminMinecraft.newConnectorSecret') }}</p>
    <pre class="overflow-x-auto rounded bg-background p-2 text-xs">{{ connectorSecretOnce }}</pre>
  </section>

  <dl class="grid max-w-2xl gap-3 text-sm">
    <div
      v-for="field in serverFields"
      :key="field.key"
      class="grid grid-cols-3 gap-2 border-b border-border pb-2"
    >
      <dt class="font-medium text-muted-foreground">{{ field.label }}</dt>
      <dd class="col-span-2 break-all">
        <Link
          v-if="field.key === 'node_name' && server.node_url"
          :href="server.node_url"
          class="text-primary hover:underline"
        >
          {{ server.node_name }}
        </Link>
        <template v-else>{{ server[field.key] }}</template>
      </dd>
    </div>
  </dl>

  <section v-if="server.plugin_config" class="mt-6 max-w-2xl">
    <h2 class="mb-2 font-semibold">{{ t('adminMinecraft.pluginConfig') }}</h2>
    <pre class="overflow-x-auto rounded border bg-muted p-3 text-xs">website-url: "{{ server.plugin_config.website_url }}"
server-id: "{{ server.plugin_config.server_id }}"
connector-secret: "{{ server.plugin_config.connector_secret }}"</pre>
  </section>

  <section v-if="server.node_managed" class="mt-6 flex flex-wrap gap-2">
    <Button v-if="controlUrls.start" as-child>
      <Link :href="controlUrls.start" method="post" as="button">{{ t('adminMinecraft.startServer') }}</Link>
    </Button>
    <Button v-if="controlUrls.stop" variant="outline" as-child>
      <Link :href="controlUrls.stop" method="post" as="button">{{ t('adminMinecraft.stopServer') }}</Link>
    </Button>
    <Button v-if="controlUrls.restart" variant="outline" as-child>
      <Link :href="controlUrls.restart" method="post" as="button">{{ t('adminMinecraft.restartServer') }}</Link>
    </Button>
  </section>

  <section v-if="controlUrls.exec" class="mt-6 max-w-xl space-y-2">
    <Label for="cmd">{{ t('adminMinecraft.remoteCommand') }}</Label>
    <div class="flex gap-2">
      <Input id="cmd" v-model="command" :placeholder="t('adminMinecraft.remoteCommandPlaceholder')" />
      <Button type="button" @click="runCommand">{{ t('adminMinecraft.runCommand') }}</Button>
    </div>
  </section>

  <section v-if="controlUrls.console" class="mt-6 max-w-xl space-y-2">
    <Label for="console-cmd">{{ t('adminMinecraft.consoleCommand') }}</Label>
    <div class="flex gap-2">
      <Input id="console-cmd" v-model="consoleCommand" :placeholder="t('adminMinecraft.consoleCommandPlaceholder')" />
      <Button type="button" variant="outline" @click="runConsoleCommand">{{ t('adminMinecraft.runCommand') }}</Button>
    </div>
  </section>

  <section v-if="controlUrls.backup || controlUrls.restore" class="mt-6 max-w-xl space-y-3">
    <h2 class="font-semibold">{{ t('adminMinecraft.worldBackup') }}</h2>
    <Button v-if="controlUrls.backup" type="button" variant="outline" @click="backupWorld">{{ t('adminMinecraft.backupNow') }}</Button>
    <div v-if="controlUrls.restore" class="flex gap-2">
      <Input v-model="restoreArchive" :placeholder="t('adminMinecraft.restoreArchivePlaceholder')" />
      <Button type="button" variant="outline" @click="restoreWorld">{{ t('adminMinecraft.restoreWorld') }}</Button>
    </div>
  </section>

  <MetricHistoryPanel v-if="metricHistory" class="mt-8" :points="metricHistory" :title="t('adminMinecraft.metricHistory')" />

  <section v-if="controlUrls.tail_logs" class="mt-6 max-w-xl space-y-2">
    <Label for="log-path">{{ t('adminMinecraft.tailLogs') }}</Label>
    <div class="flex gap-2">
      <Input id="log-path" v-model="logPath" :placeholder="t('adminMinecraft.tailLogsPlaceholder')" />
      <Button type="button" variant="outline" @click="tailLogs">{{ t('adminMinecraft.tailLogsRun') }}</Button>
    </div>
  </section>

  <NodeTasksTable :tasks="nodeTasks" />

  <div class="mt-6 flex flex-wrap gap-2">
    <template v-for="action in actions" :key="action.href">
      <Button v-if="action.method === 'post'" variant="outline" as-child>
        <Link :href="action.href" method="post" as="button" :data="{ confirm: action.confirm }">{{ action.label }}</Link>
      </Button>
      <Button v-else-if="action.method === 'delete'" variant="destructive" as-child>
        <Link :href="action.href" method="delete" as="button" :data="{ confirm: action.confirm }">{{ action.label }}</Link>
      </Button>
      <Button v-else variant="outline" as-child>
        <a :href="action.href">{{ action.label }}</a>
      </Button>
    </template>
    <Button variant="ghost" as-child>
      <a :href="backUrl">{{ t('adminMinecraft.backToServers') }}</a>
    </Button>
    <Button variant="ghost" as-child>
      <Link :href="adminRoutes.minecraftPlayers">{{ t('adminMinecraft.players') }}</Link>
    </Button>
  </div>
</template>
