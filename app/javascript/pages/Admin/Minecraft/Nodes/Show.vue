<script setup lang="ts">
import { computed } from 'vue'
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import AdminAlertBanners, { type AdminAlert } from '@/components/admin/AdminAlertBanners.vue'
import NodeTasksTable, { type NodeTaskRow } from '@/components/admin/NodeTasksTable.vue'
import MetricHistoryPanel, { type MetricPoint } from '@/components/admin/MetricHistoryPanel.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: AdminLayout })

interface ConnectorProxyEntry {
  last_request_at?: string
  last_success_at?: string
  last_error?: string
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
  actions: Array<{ label: string; href: string; method?: string; confirm?: string }>
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
</script>

<template>
  <PageHeader :title="title" />

  <AdminAlertBanners :alerts="alerts" />

  <section
    v-if="nodeSecretOnce"
    class="mb-4 max-w-2xl rounded border border-amber-500/40 bg-amber-500/10 p-4 text-sm"
  >
    <p class="mb-2 font-medium">{{ t('adminMinecraft.newNodeSecret') }}</p>
    <pre class="overflow-x-auto rounded bg-background p-2 text-xs">{{ nodeSecretOnce }}</pre>
  </section>

  <section
    v-if="pairingTokenOnce"
    class="mb-4 max-w-2xl rounded border border-amber-500/40 bg-amber-500/10 p-4 text-sm"
  >
    <p class="mb-2 font-medium">
      {{ t('adminMinecraft.newPairingToken') }}
      <span v-if="pairingTokenExpiresAt" class="font-normal text-muted-foreground">
        ({{ pairingTokenExpiresAt }})
      </span>
    </p>
    <pre class="overflow-x-auto rounded bg-background p-2 text-xs">{{ pairingTokenOnce }}</pre>
  </section>

  <dl class="grid max-w-2xl gap-3 text-sm">
    <div
      v-for="field in nodeFields"
      :key="field.key"
      class="grid grid-cols-3 gap-2 border-b border-border pb-2"
    >
      <dt class="font-medium text-muted-foreground">{{ field.label }}</dt>
      <dd class="col-span-2 break-all">{{ node[field.key as keyof typeof node] }}</dd>
    </div>
  </dl>

  <section v-if="hostMetricRows.length" class="mt-8 max-w-2xl">
    <h2 class="mb-3 text-lg font-semibold">{{ t('adminMinecraft.hostMetrics') }}</h2>
    <dl class="grid gap-2 text-sm">
      <div
        v-for="row in hostMetricRows"
        :key="row.key"
        class="grid grid-cols-3 gap-2 border-b border-border pb-2"
      >
        <dt class="font-medium text-muted-foreground">{{ row.key }}</dt>
        <dd class="col-span-2 break-all">{{ row.value }}</dd>
      </div>
    </dl>
  </section>

  <MetricHistoryPanel v-if="metricHistory" class="mt-8" :points="metricHistory" :title="t('adminMinecraft.metricHistory')" />

  <section v-if="connectorProxyRows.length" class="mt-8">
    <h2 class="mb-3 text-lg font-semibold">{{ t('adminMinecraft.connectorProxy') }}</h2>
    <div class="overflow-x-auto rounded-md border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>{{ t('adminMinecraft.fieldServerId') }}</TableHead>
            <TableHead>{{ t('adminMinecraft.lastRequestAt') }}</TableHead>
            <TableHead>{{ t('adminMinecraft.lastSuccessAt') }}</TableHead>
            <TableHead>{{ t('adminMinecraft.lastError') }}</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="row in connectorProxyRows" :key="row.serverId">
            <TableCell class="font-mono text-xs">{{ row.serverId }}</TableCell>
            <TableCell class="text-xs">{{ row.lastRequestAt }}</TableCell>
            <TableCell class="text-xs">{{ row.lastSuccessAt }}</TableCell>
            <TableCell class="max-w-xs truncate text-xs text-red-700 dark:text-red-400">{{ row.lastError }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>
  </section>

  <NodeTasksTable :tasks="nodeTasks" />

  <section v-if="servers.length" class="mt-8">
    <h2 class="mb-3 text-lg font-semibold">{{ t('adminMinecraft.managedServers') }}</h2>
    <ul class="space-y-2">
      <li v-for="s in servers" :key="s.public_id">
        <Link :href="s.url" class="text-primary hover:underline">{{ s.name }}</Link>
        <span class="ml-2 text-muted-foreground">({{ s.process_state }})</span>
      </li>
    </ul>
  </section>

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
      <a :href="backUrl">{{ t('adminMinecraft.backToNodes') }}</a>
    </Button>
  </div>
</template>
