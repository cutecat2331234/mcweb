<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { FileItem } from '@arco-design/web-vue'
import {
  Alert,
  Button,
  Card,
  Checkbox,
  Collapse,
  CollapseItem,
  Descriptions,
  DescriptionsItem,
  Drawer,
  Empty,
  Form,
  FormItem,
  Input,
  Modal,
  PageHeader,
  Radio,
  RadioGroup,
  Space,
  Table,
  TableColumn,
  Tag,
  Timeline,
  TimelineItem,
  Upload,
} from '@mcweb/ui'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
const SHA256_PATTERN = /^[0-9a-f]{64}$/i

interface CatalogItem {
  id: string
  label: string
  description: string
  always_on?: boolean
  enabled?: boolean
  ruby_namespaces?: string[]
  admin_module_key?: string
  path_prefixes?: string[]
  kind?: string
  host?: string
  capabilities?: string[]
  limitations?: string[]
}

interface PluginItem {
  id: string
  name: string
  version: string
  api_version: string
  description?: string | null
  author?: string | null
  homepage?: string | null
  requires: Record<string, string>
  capabilities: string[]
  status: string
  listener_count: number
  failure_count: number
  last_error?: string | null
  activation_order?: number | null
  contribution_count: number
  contribution_descriptors: Array<{
    id: string
    type: string
    priority: number
    before: string[]
    after: string[]
    requires: string[]
    conflicts: string[]
    payload: Record<string, unknown>
  }>
}

interface PluginDiagnostic {
  level: string
  code: string
  phase: string
  plugin_id?: string | null
  event?: string | null
  message: string
  exception?: string | null
  occurred_at?: string | null
}

interface MarketplacePlugin {
  id: string
  name: string
  version: string
  api_version: string
  status: string
  filesystem_status: string
  runtime_status?: string | null
  source?: { scheme?: string; host?: string }
  sha256?: string | null
  updated_at?: string | null
  recoverable: boolean
  rollback_available: boolean
  data_mode?: 'preserve_data' | 'purge_data' | null
  health: {
    status: string
    expected_count: number
    actual_count: number
    missing_count: number
    modified_count: number
    unknown_count: number
  }
}

interface MarketplaceOperation {
  operation_id: string
  action: string
  status: string
  plugin_id?: string | null
  version?: string | null
  message?: string | null
  occurred_at?: string | null
  recoverable: boolean
}

interface MarketplaceSnapshot {
  available: boolean
  plugins: MarketplacePlugin[]
  errors: Array<{ code: string; message: string }>
  operations: MarketplaceOperation[]
}

interface PluginRuntimeGeneration {
  number: number
  state: string
  action: string
  target_plugin_id?: string | null
  desired_plugins: Record<string, string>
  minimum_ack_ratio: number
  expected_process_count: number
  deadline_at?: string | null
  activated_at?: string | null
  error_code?: string | null
  error_message?: string | null
  acknowledgements: Array<{
    process_ref: string
    process_kind: string
    status: string
    plugin_versions: Record<string, string>
    error_code?: string | null
    error_message?: string | null
    acked_at?: string | null
    last_seen_at?: string | null
  }>
}

interface PluginLifecycleInstallation {
  plugin_id: string
  current_version?: string | null
  desired_state: string
  current_state: string
  active_generation_number?: number | null
  last_operation_id?: string | null
  error_code?: string | null
  error_message?: string | null
  updated_at?: string | null
}

interface PluginLifecycleRun {
  operation_id: string
  plugin_id?: string | null
  action: string
  state: string
  actor?: string | null
  from_version?: string | null
  to_version?: string | null
  generation_number?: number | null
  dry_run: boolean
  maintenance_mode: boolean
  retryable: boolean
  error_code?: string | null
  error_message?: string | null
  recovery_path: boolean
  started_at?: string | null
  completed_at?: string | null
  steps: Array<{
    sequence: number
    step_key: string
    state: string
    retryable: boolean
    error_code?: string | null
    error_message?: string | null
    started_at?: string | null
    completed_at?: string | null
  }>
}

interface PluginCatalogRelease {
  id: number
  plugin_id: string
  version: string
  api_version: string
  state: 'active' | 'disabled' | 'rollback' | 'uninstalled'
  health: string
  manifest_sha256: string
  package_sha256: string
  package_digest_source: 'receipt' | 'derived'
  operation_id?: string | null
  observed_at?: string | null
  manifest: {
    name?: string | null
    capabilities: string[]
  }
  diagnostics: Array<{
    code: string
    severity: 'warning' | 'error'
  }>
  contributions: Array<{
    id: string
    type: string
    descriptor_sha256: string
    schema_sha256?: string | null
  }>
  file_count: number
  file_health_counts: Record<string, number>
  file_issues: Array<{
    path: string
    health: string
    expected_size: number
    observed_size?: number | null
    sha256: string
    observed_sha256?: string | null
  }>
}

const props = defineProps<{
  title: string
  platform: CatalogItem[]
  applications: CatalogItem[]
  extensions: CatalogItem[]
  plugins: PluginItem[]
  pluginDiagnostics: PluginDiagnostic[]
  pluginMarketplace: MarketplaceSnapshot
  pluginLifecycle: {
    available: boolean
    installations: PluginLifecycleInstallation[]
    runs: PluginLifecycleRun[]
  }
  pluginCatalog: {
    available: boolean
    releases: PluginCatalogRelease[]
  }
  pluginRuntimeGenerations: {
    available: boolean
    generations: PluginRuntimeGeneration[]
  }
  pluginActions: {
    install: string
    enable: string
    disable: string
    uninstall: string
    recover: string
    rollback: string
    health: string
    reconcileCatalog: string
  }
  canManagePlugins: boolean
  pluginCapabilities: {
    install: boolean
    enable: boolean
    disable: boolean
    diagnostics: boolean
    recover: boolean
    rollback: boolean
    uninstall_preserve: boolean
    uninstall_purge: boolean
  }
  freelyExtensible: boolean
  featureFlagsUrl: string
}>()

const pluginFiles = ref<FileItem[]>([])
const selectedLifecycleRun = ref<PluginLifecycleRun | null>(null)
const selectedCatalogRelease = ref<PluginCatalogRelease | null>(null)
const uninstallTarget = ref<MarketplacePlugin | null>(null)
const uninstallConfirmation = ref('')
const uninstallSubmitting = ref(false)
const uninstallDataMode = ref<'preserve_data' | 'purge_data'>('preserve_data')
const uninstallModalVisible = computed({
  get: () => uninstallTarget.value !== null,
  set: (visible: boolean) => {
    if (!visible) closeUninstall()
  },
})
const canUninstall = computed(
  () => uninstallTarget.value !== null &&
    hasVerifiedUninstallIdentity(uninstallTarget.value) &&
    uninstallConfirmation.value.trim() === uninstallTarget.value.id &&
    (
      uninstallDataMode.value === 'purge_data'
        ? props.pluginCapabilities.uninstall_purge
        : props.pluginCapabilities.uninstall_preserve
    ),
)
const installForm = useForm<{
  plugin_package: File | null
  expected_sha256: string
  expected_id: string
  allow_downgrade: boolean
  dry_run: boolean
  maintenance_mode: boolean
}>({
  plugin_package: null,
  expected_sha256: '',
  expected_id: '',
  allow_downgrade: false,
  dry_run: false,
  maintenance_mode: false,
})

function pluginStatusColor(status: string) {
  if (status === 'active') return 'green'
  if (status === 'degraded') return 'orange'
  if (status === 'disabled') return 'red'
  return 'gray'
}

function diagnosticColor(level: string) {
  if (level === 'error') return 'red'
  if (level === 'warning') return 'orange'
  return 'blue'
}

function pluginStatusLabel(status: string) {
  const known = ['registered', 'active', 'degraded', 'disabled']
  return known.includes(status)
    ? t(`admin.applications.pluginStatus.${status}`)
    : status
}

function marketplaceStatusLabel(status: string | null | undefined) {
  if (!status) return '—'
  const known = [
    'active',
    'installed',
    'disabled',
    'uninstalled',
    'rollback',
    'not_loaded',
    'succeeded',
    'failed',
    'started',
    'healthy',
    'changed',
    'missing',
    'unavailable',
    'untracked',
    'not_installed',
    'modified',
    'unknown',
  ]
  return known.includes(status)
    ? t(`admin.applications.marketplace.statusLabels.${status}`)
    : status
}

function marketplaceStatusColor(status: string) {
  if (['active', 'installed', 'succeeded', 'healthy'].includes(status)) return 'green'
  if ([
    'disabled',
    'not_loaded',
    'started',
    'untracked',
    'unavailable',
    'unknown',
    'rollback',
  ].includes(status)) return 'orange'
  if (['failed', 'changed', 'missing', 'modified'].includes(status)) return 'red'
  return 'gray'
}

function generationStatusColor(status: string) {
  if (status === 'active') return 'green'
  if (['pending', 'rolling_back'].includes(status)) return 'orange'
  if (['failed', 'rolled_back'].includes(status)) return 'red'
  return 'gray'
}

function lifecycleStatusColor(status: string) {
  if (['enabled', 'installed', 'succeeded', 'recovered'].includes(status)) return 'green'
  if ([
    'running',
    'uploaded',
    'validated',
    'staged',
    'installing',
    'enabling',
    'disabling',
    'upgrading',
    'uninstalling',
    'rolling_back',
  ].includes(status)) return 'orange'
  if (['failed', 'interrupted', 'quarantined'].includes(status)) return 'red'
  return 'gray'
}

function lifecycleLabel(status: string) {
  return t(`admin.applications.lifecycle.states.${status}`)
}

function contributionTypeLabel(type: string) {
  const known = [
    'permission',
    'settings',
    'job',
    'navigation',
    'page',
    'ui_slot',
    'translation',
    'event',
    'entity_metadata',
  ]
  return known.includes(type)
    ? t(`admin.applications.contributions.types.${type}`)
    : type
}

function contributionPayloadSummary(payload: Record<string, unknown>) {
  return Object.entries(payload)
    .slice(0, 6)
    .map(([key, value]) => {
      const rendered = typeof value === 'string' || typeof value === 'number' ||
        typeof value === 'boolean'
        ? String(value)
        : Array.isArray(value)
          ? value.slice(0, 4).join(', ')
          : Object.keys((value ?? {}) as Record<string, unknown>).slice(0, 4).join(', ')
      return `${key}: ${rendered || '—'}`
    })
    .join(' · ')
}

function handlePluginPackageChange(files: FileItem[]) {
  pluginFiles.value = files.slice(-1)
  installForm.plugin_package = pluginFiles.value[0]?.file ?? null
}

function installPlugin() {
  installForm.post(props.pluginActions.install, {
    forceFormData: true,
    preserveScroll: true,
    onSuccess: () => {
      installForm.reset('plugin_package', 'expected_sha256', 'expected_id')
      pluginFiles.value = []
    },
  })
}

function lifecycleActionLabel(key: 'install' | 'enable' | 'disable' | 'recover' | 'rollback' | 'uninstall') {
  const label = t(`admin.applications.marketplace.${key}`)
  return installForm.dry_run
    ? t('admin.applications.marketplace.dryRunAction', { action: label })
    : label
}

function changePluginState(action: 'enable' | 'disable', pluginId: string) {
  router.post(
    props.pluginActions[action],
    {
      plugin_id: pluginId,
      dry_run: installForm.dry_run,
      maintenance_mode: installForm.maintenance_mode,
    },
    { preserveScroll: true },
  )
}

function openUninstall(plugin: MarketplacePlugin) {
  if (!hasVerifiedUninstallIdentity(plugin)) return

  uninstallTarget.value = plugin
  uninstallConfirmation.value = ''
  uninstallDataMode.value = props.pluginCapabilities.uninstall_preserve
    ? 'preserve_data'
    : 'purge_data'
}

function hasVerifiedUninstallIdentity(plugin: MarketplacePlugin) {
  return plugin.version.length > 0 &&
    typeof plugin.sha256 === 'string' &&
    SHA256_PATTERN.test(plugin.sha256)
}

function closeUninstall() {
  if (uninstallSubmitting.value) return
  uninstallTarget.value = null
  uninstallConfirmation.value = ''
  uninstallDataMode.value = 'preserve_data'
}

function checkPluginHealth(pluginId: string) {
  router.post(
    props.pluginActions.health,
    { plugin_id: pluginId },
    { preserveScroll: true },
  )
}

function reconcilePluginCatalog() {
  router.post(
    props.pluginActions.reconcileCatalog,
    {},
    { preserveScroll: true },
  )
}

function recoverPlugin(plugin: MarketplacePlugin) {
  if (!plugin.sha256 || !hasVerifiedUninstallIdentity(plugin)) return

  router.post(
    props.pluginActions.recover,
    {
      plugin_id: plugin.id,
      expected_version: plugin.version,
      expected_sha256: plugin.sha256,
      dry_run: installForm.dry_run,
      maintenance_mode: installForm.maintenance_mode,
    },
    { preserveScroll: true },
  )
}

function rollbackPlugin(plugin: MarketplacePlugin) {
  if (!plugin.sha256 || !hasVerifiedUninstallIdentity(plugin)) return

  Modal.warning({
    title: t('admin.applications.marketplace.rollbackTitle'),
    content: t('admin.applications.marketplace.rollbackConfirm', {
      plugin: plugin.name,
      version: plugin.version,
    }),
    okText: t('admin.applications.marketplace.rollback'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    onOk: () => {
      router.post(
        props.pluginActions.rollback,
        {
          plugin_id: plugin.id,
          expected_version: plugin.version,
          expected_sha256: plugin.sha256,
          dry_run: installForm.dry_run,
          maintenance_mode: installForm.maintenance_mode,
        },
        { preserveScroll: true },
      )
    },
  })
}

function submitUninstall() {
  const target = uninstallTarget.value
  if (!target || !target.sha256 || !canUninstall.value) return

  router.delete(props.pluginActions.uninstall, {
    data: {
      plugin_id: target.id,
      confirmation: uninstallConfirmation.value.trim(),
      expected_version: target.version,
      expected_sha256: target.sha256,
      data_mode: uninstallDataMode.value,
      dry_run: installForm.dry_run,
      maintenance_mode: installForm.maintenance_mode,
    },
    preserveScroll: true,
    onStart: () => {
      uninstallSubmitting.value = true
    },
    onSuccess: () => {
      uninstallTarget.value = null
      uninstallConfirmation.value = ''
      uninstallDataMode.value = 'preserve_data'
    },
    onFinish: () => {
      uninstallSubmitting.value = false
    },
  })
}
</script>

<template>
  <a-page-header
    :title="title"
    :subtitle="t('admin.applications.subtitle')"
    class="mb-5 !px-0"
  />

  <a-alert
    type="warning"
    show-icon
    :title="t('admin.applications.trustedPluginWarning')"
    class="mb-6"
  >
    {{ t('admin.applications.readDocs') }}
  </a-alert>

  <section class="mb-8">
    <h2 class="mb-1 text-lg font-semibold">
      {{ t('admin.applications.marketplace.title') }}
    </h2>
    <p class="mb-4 text-sm text-muted-foreground">
      {{ t('admin.applications.marketplace.hint') }}
    </p>

    <a-space
      v-if="canManagePlugins"
      wrap
      class="mb-4"
      :size="[20, 8]"
    >
      <a-checkbox v-model="installForm.dry_run">
        {{ t('admin.applications.marketplace.dryRun') }}
      </a-checkbox>
      <a-checkbox v-model="installForm.maintenance_mode">
        {{ t('admin.applications.marketplace.maintenanceMode') }}
      </a-checkbox>
      <span class="text-xs text-muted-foreground">
        {{
          installForm.dry_run
            ? t('admin.applications.marketplace.dryRunHint')
            : t('admin.applications.marketplace.maintenanceModeHint')
        }}
      </span>
    </a-space>

    <a-space
      v-if="pluginMarketplace.errors.length"
      direction="vertical"
      fill
      class="mb-4"
    >
      <a-alert
        v-for="error in pluginMarketplace.errors"
        :key="`${error.code}-${error.message}`"
        type="warning"
        show-icon
        :title="t('admin.applications.marketplace.errorsTitle')"
      >
        {{ error.message }}
      </a-alert>
    </a-space>

    <div class="grid gap-4 xl:grid-cols-2">
      <a-card
        v-if="pluginCapabilities.install"
        :title="t('admin.applications.marketplace.installTitle')"
        :bordered="false"
      >
        <a-form :model="installForm" layout="vertical" @submit="installPlugin">
          <a-form-item
            field="plugin_package"
            :label="t('admin.applications.marketplace.packageLabel')"
            :extra="t('admin.applications.marketplace.packageHint')"
          >
            <a-upload
              :file-list="pluginFiles"
              :auto-upload="false"
              :limit="1"
              accept=".zip,application/zip"
              @change="handlePluginPackageChange"
            />
          </a-form-item>
          <a-form-item
            field="expected_sha256"
            :label="t('admin.applications.marketplace.checksumLabel')"
            :extra="t('admin.applications.marketplace.checksumHint')"
          >
            <a-input
              v-model="installForm.expected_sha256"
              :max-length="64"
              allow-clear
            />
          </a-form-item>
          <a-form-item
            field="expected_id"
            :label="t('admin.applications.marketplace.expectedIdLabel')"
            :extra="t('admin.applications.marketplace.expectedIdHint')"
          >
            <a-input v-model="installForm.expected_id" allow-clear />
          </a-form-item>
          <a-form-item field="allow_downgrade">
            <a-checkbox v-model="installForm.allow_downgrade">
              {{ t('admin.applications.marketplace.allowDowngrade') }}
            </a-checkbox>
          </a-form-item>
          <a-button
            type="primary"
            html-type="submit"
            :loading="installForm.processing"
            :disabled="!installForm.plugin_package || installForm.expected_sha256.length !== 64"
          >
            {{ lifecycleActionLabel('install') }}
          </a-button>
        </a-form>
      </a-card>

      <a-card
        :title="t('admin.applications.marketplace.managedTitle')"
        :bordered="false"
      >
        <a-space
          v-if="pluginMarketplace.plugins.length"
          direction="vertical"
          fill
        >
          <a-card
            v-for="plugin in pluginMarketplace.plugins"
            :key="plugin.id"
            :bordered="false"
            class="bg-[var(--color-fill-1)]"
          >
            <template #title>
              <a-space wrap>
                <span>{{ plugin.name }}</span>
                <a-tag :color="marketplaceStatusColor(plugin.status)">
                  {{ marketplaceStatusLabel(plugin.status) }}
                </a-tag>
                <a-tag>v{{ plugin.version }}</a-tag>
              </a-space>
            </template>
            <a-descriptions
              :column="{ xs: 1, sm: 2 }"
              layout="vertical"
              :bordered="false"
            >
              <a-descriptions-item :label="t('admin.applications.pluginIdLabel')">
                {{ plugin.id }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.applications.marketplace.filesystemStatus')">
                {{ marketplaceStatusLabel(plugin.filesystem_status) }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.applications.marketplace.runtimeStatus')">
                {{ marketplaceStatusLabel(plugin.runtime_status) }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="plugin.sha256"
                :label="t('admin.applications.marketplace.checksum')"
              >
                {{ plugin.sha256 }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="plugin.source?.scheme || plugin.source?.host"
                :label="t('admin.applications.marketplace.source')"
              >
                {{ [plugin.source?.scheme, plugin.source?.host].filter(Boolean).join(' · ') }}
              </a-descriptions-item>
              <a-descriptions-item
                v-if="plugin.updated_at"
                :label="t('admin.applications.marketplace.updatedAt')"
              >
                {{ plugin.updated_at }}
              </a-descriptions-item>
              <a-descriptions-item :label="t('admin.applications.marketplace.fileHealth')">
                <a-space wrap>
                  <a-tag :color="marketplaceStatusColor(plugin.health.status)">
                    {{ marketplaceStatusLabel(plugin.health.status) }}
                  </a-tag>
                  <span
                    v-if="plugin.health.status === 'changed'"
                    class="text-xs text-muted-foreground"
                  >
                    {{
                      t('admin.applications.marketplace.fileHealthSummary', {
                        missing: plugin.health.missing_count,
                        modified: plugin.health.modified_count,
                        unknown: plugin.health.unknown_count,
                      })
                    }}
                  </span>
                </a-space>
              </a-descriptions-item>
              <a-descriptions-item
                v-if="plugin.data_mode"
                :label="t('admin.applications.marketplace.lastDataMode')"
              >
                {{ t(`admin.applications.marketplace.dataModes.${plugin.data_mode}.label`) }}
              </a-descriptions-item>
            </a-descriptions>
            <a-space v-if="canManagePlugins" wrap class="mt-3">
              <a-button
                v-if="pluginCapabilities.diagnostics &&
                  ['installed', 'disabled'].includes(plugin.filesystem_status)"
                size="small"
                @click="checkPluginHealth(plugin.id)"
              >
                {{ t('admin.applications.marketplace.checkHealth') }}
              </a-button>
              <a-button
                v-if="pluginCapabilities.enable &&
                  plugin.filesystem_status === 'disabled'"
                size="small"
                @click="changePluginState('enable', plugin.id)"
              >
                {{ lifecycleActionLabel('enable') }}
              </a-button>
              <a-button
                v-if="pluginCapabilities.disable &&
                  plugin.filesystem_status === 'installed'"
                size="small"
                @click="changePluginState('disable', plugin.id)"
              >
                {{ lifecycleActionLabel('disable') }}
              </a-button>
              <a-button
                v-if="pluginCapabilities.recover &&
                  plugin.filesystem_status === 'uninstalled' &&
                  plugin.recoverable &&
                  hasVerifiedUninstallIdentity(plugin)"
                size="small"
                type="primary"
                @click="recoverPlugin(plugin)"
              >
                {{ lifecycleActionLabel('recover') }}
              </a-button>
              <a-button
                v-if="pluginCapabilities.rollback &&
                  plugin.filesystem_status === 'installed' &&
                  plugin.rollback_available &&
                  hasVerifiedUninstallIdentity(plugin)"
                size="small"
                status="warning"
                @click="rollbackPlugin(plugin)"
              >
                {{ lifecycleActionLabel('rollback') }}
              </a-button>
              <a-button
                v-if="(pluginCapabilities.uninstall_preserve ||
                  pluginCapabilities.uninstall_purge) &&
                  ['installed', 'disabled'].includes(plugin.filesystem_status) &&
                  hasVerifiedUninstallIdentity(plugin)"
                size="small"
                status="danger"
                @click="openUninstall(plugin)"
              >
                {{ lifecycleActionLabel('uninstall') }}
              </a-button>
            </a-space>
          </a-card>
        </a-space>
        <a-empty
          v-else
          :description="t('admin.applications.marketplace.noManagedPlugins')"
        />
      </a-card>
    </div>

    <a-card
      class="mt-4"
      :title="t('admin.applications.marketplace.operationsTitle')"
      :bordered="false"
    >
      <a-table
        :data="pluginMarketplace.operations"
        :pagination="false"
        :bordered="false"
        :scroll="{ minWidth: 960 }"
      >
        <template #columns>
          <a-table-column
            :title="t('admin.applications.marketplace.action')"
            data-index="action"
            :width="130"
          />
          <a-table-column
            :title="t('admin.applications.marketplace.status')"
            :width="130"
          >
            <template #cell="{ record }">
              <a-tag :color="marketplaceStatusColor(record.status)">
                {{ marketplaceStatusLabel(record.status) }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.applications.marketplace.plugin')"
            data-index="plugin_id"
            :width="190"
          />
          <a-table-column
            :title="t('admin.applications.marketplace.version')"
            data-index="version"
            :width="120"
          />
          <a-table-column
            :title="t('admin.applications.marketplace.message')"
            data-index="message"
          />
          <a-table-column
            :title="t('admin.applications.marketplace.time')"
            data-index="occurred_at"
            :width="210"
          />
        </template>
        <template #empty>
          <a-empty :description="t('admin.applications.marketplace.noOperations')" />
        </template>
      </a-table>
    </a-card>
  </section>

  <section v-if="pluginCapabilities.diagnostics" class="mb-8">
    <div class="mb-4 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 class="text-lg font-semibold">
          {{ t('admin.applications.catalog.title') }}
        </h2>
        <p class="text-sm text-muted-foreground">
          {{ t('admin.applications.catalog.hint') }}
        </p>
      </div>
      <a-button type="primary" @click="reconcilePluginCatalog">
        {{ t('admin.applications.catalog.reconcile') }}
      </a-button>
    </div>

    <a-alert
      v-if="!pluginCatalog.available"
      type="warning"
      show-icon
      :title="t('admin.applications.catalog.unavailable')"
    />
    <a-card v-else :bordered="false">
      <a-table
        :data="pluginCatalog.releases"
        :pagination="{ pageSize: 12, hideOnSinglePage: true }"
        :bordered="false"
        :scroll="{ minWidth: 980 }"
      >
        <template #columns>
          <a-table-column
            :title="t('admin.applications.catalog.plugin')"
            :width="230"
          >
            <template #cell="{ record }">
              <a-space direction="vertical" size="mini">
                <strong>{{ record.manifest.name || record.plugin_id }}</strong>
                <span class="font-mono text-xs text-muted-foreground">
                  {{ record.plugin_id }}
                </span>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.applications.catalog.version')"
            data-index="version"
            :width="120"
          />
          <a-table-column
            :title="t('admin.applications.catalog.state')"
            :width="130"
          >
            <template #cell="{ record }">
              <a-tag :color="marketplaceStatusColor(record.state)">
                {{ marketplaceStatusLabel(record.state) }}
              </a-tag>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.applications.catalog.health')"
            :width="150"
          >
            <template #cell="{ record }">
              <a-space>
                <a-tag :color="marketplaceStatusColor(record.health)">
                  {{ marketplaceStatusLabel(record.health) }}
                </a-tag>
                <a-tag v-if="record.diagnostics.length" color="red">
                  {{ record.diagnostics.length }}
                </a-tag>
              </a-space>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.applications.catalog.contents')"
            :width="220"
          >
            <template #cell="{ record }">
              {{
                t('admin.applications.catalog.contentCounts', {
                  contributions: record.contributions.length,
                  files: record.file_count,
                })
              }}
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.applications.catalog.observedAt')"
            data-index="observed_at"
            :width="210"
          />
          <a-table-column
            :title="t('admin.applications.catalog.details')"
            :width="110"
            fixed="right"
          >
            <template #cell="{ record }">
              <a-button
                type="text"
                size="small"
                @click="selectedCatalogRelease = record"
              >
                {{ t('admin.applications.catalog.view') }}
              </a-button>
            </template>
          </a-table-column>
        </template>
        <template #empty>
          <a-empty :description="t('admin.applications.catalog.empty')" />
        </template>
      </a-table>
    </a-card>
  </section>

  <section v-if="pluginCapabilities.diagnostics" class="mb-8">
    <div class="mb-4">
      <h2 class="text-lg font-semibold">
        {{ t('admin.applications.lifecycle.title') }}
      </h2>
      <p class="text-sm text-muted-foreground">
        {{ t('admin.applications.lifecycle.hint') }}
      </p>
    </div>

    <a-alert
      v-if="!pluginLifecycle.available"
      type="warning"
      show-icon
      :title="t('admin.applications.lifecycle.unavailable')"
    />
    <a-space v-else direction="vertical" :size="16" fill>
      <a-card :title="t('admin.applications.lifecycle.installationsTitle')">
        <a-table
          :data="pluginLifecycle.installations"
          :pagination="false"
          :bordered="false"
          :scroll="{ minWidth: 760 }"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.lifecycle.plugin')"
              data-index="plugin_id"
            />
            <a-table-column
              :title="t('admin.applications.lifecycle.version')"
              data-index="current_version"
              :width="130"
            />
            <a-table-column
              :title="t('admin.applications.lifecycle.currentState')"
              :width="150"
            >
              <template #cell="{ record }">
                <a-tag :color="lifecycleStatusColor(record.current_state)">
                  {{ lifecycleLabel(record.current_state) }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.lifecycle.desiredState')"
              :width="150"
            >
              <template #cell="{ record }">
                {{ lifecycleLabel(record.desired_state) }}
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.lifecycle.generation')"
              data-index="active_generation_number"
              :width="130"
            />
            <a-table-column
              :title="t('admin.applications.lifecycle.updatedAt')"
              data-index="updated_at"
              :width="210"
            />
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.lifecycle.noInstallations')" />
          </template>
        </a-table>
      </a-card>

      <a-card :title="t('admin.applications.lifecycle.runsTitle')">
        <a-table
          :data="pluginLifecycle.runs"
          :pagination="{ pageSize: 10, hideOnSinglePage: true }"
          :bordered="false"
          :scroll="{ minWidth: 840 }"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.lifecycle.plugin')"
              data-index="plugin_id"
            />
            <a-table-column
              :title="t('admin.applications.lifecycle.action')"
              :width="130"
            >
              <template #cell="{ record }">
                {{ t(`admin.applications.generations.actions.${record.action}`) }}
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.lifecycle.runState')"
              :width="130"
            >
              <template #cell="{ record }">
                <a-tag :color="lifecycleStatusColor(record.state)">
                  {{ lifecycleLabel(record.state) }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.lifecycle.versionChange')"
              :width="190"
            >
              <template #cell="{ record }">
                {{ record.from_version || '—' }} → {{ record.to_version || '—' }}
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.lifecycle.startedAt')"
              data-index="started_at"
              :width="210"
            />
            <a-table-column
              :title="t('admin.applications.lifecycle.details')"
              :width="120"
              fixed="right"
            >
              <template #cell="{ record }">
                <a-button
                  type="text"
                  size="small"
                  @click="selectedLifecycleRun = record"
                >
                  {{ t('admin.applications.lifecycle.view') }}
                </a-button>
              </template>
            </a-table-column>
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.lifecycle.noRuns')" />
          </template>
        </a-table>
      </a-card>
    </a-space>
  </section>

  <section v-if="pluginCapabilities.diagnostics" class="mb-8">
    <div class="mb-4">
      <h2 class="text-lg font-semibold">
        {{ t('admin.applications.generations.title') }}
      </h2>
      <p class="text-sm text-muted-foreground">
        {{ t('admin.applications.generations.hint') }}
      </p>
    </div>

    <a-alert
      v-if="!pluginRuntimeGenerations.available"
      type="warning"
      show-icon
      :title="t('admin.applications.generations.unavailable')"
    />
    <a-collapse
      v-else-if="pluginRuntimeGenerations.generations.length"
      :bordered="false"
      accordion
    >
      <a-collapse-item
        v-for="generation in pluginRuntimeGenerations.generations"
        :key="generation.number"
        :header="t('admin.applications.generations.generation', { number: generation.number })"
      >
        <template #extra>
          <a-space wrap>
            <a-tag :color="generationStatusColor(generation.state)">
              {{ t(`admin.applications.generations.states.${generation.state}`) }}
            </a-tag>
            <a-tag>
              {{ t(`admin.applications.generations.actions.${generation.action}`) }}
            </a-tag>
          </a-space>
        </template>

        <a-descriptions
          :column="{ xs: 1, sm: 2, lg: 4 }"
          layout="vertical"
          size="small"
          :bordered="false"
        >
          <a-descriptions-item :label="t('admin.applications.generations.target')">
            {{ generation.target_plugin_id || '—' }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.generations.requiredAcks')">
            {{
              t('admin.applications.generations.requiredAcksValue', {
                count: generation.expected_process_count,
                ratio: Math.round(generation.minimum_ack_ratio * 100),
              })
            }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.generations.deadline')">
            {{ generation.deadline_at || '—' }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.generations.activatedAt')">
            {{ generation.activated_at || '—' }}
          </a-descriptions-item>
        </a-descriptions>

        <a-alert
          v-if="generation.error_code || generation.error_message"
          class="mb-3"
          type="error"
          :title="t('admin.applications.generations.error')"
        >
          {{ generation.error_message }}
        </a-alert>

        <a-table
          :data="generation.acknowledgements"
          :pagination="false"
          :bordered="false"
          :scroll="{ minWidth: 760 }"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.generations.process')"
              :width="170"
            >
              <template #cell="{ record }">
                <span class="font-mono text-xs">
                  {{ record.process_kind }} · {{ record.process_ref }}
                </span>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.generations.status')"
              :width="120"
            >
              <template #cell="{ record }">
                <a-tag :color="record.status === 'healthy' ? 'green' : 'red'">
                  {{ t(`admin.applications.generations.ackStates.${record.status}`) }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.generations.loadedPlugins')"
            >
              <template #cell="{ record }">
                <a-space v-if="Object.keys(record.plugin_versions).length" wrap>
                  <a-tag
                    v-for="(version, pluginId) in record.plugin_versions"
                    :key="pluginId"
                    bordered
                  >
                    {{ pluginId }} · {{ version }}
                  </a-tag>
                </a-space>
                <span v-else>—</span>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.generations.lastSeen')"
              data-index="last_seen_at"
              :width="210"
            />
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.generations.noAcks')" />
          </template>
        </a-table>
      </a-collapse-item>
    </a-collapse>
    <a-empty
      v-else
      :description="t('admin.applications.generations.empty')"
    />
  </section>

  <section class="mb-8">
    <h2 class="mb-1 text-lg font-semibold">{{ t('admin.applications.platformTitle') }}</h2>
    <p class="mb-4 text-sm text-muted-foreground">{{ t('admin.applications.platformHint') }}</p>
    <div class="grid gap-3 md:grid-cols-2">
      <a-card
        v-for="item in platform"
        :key="item.id"
        :bordered="false"
        class="bg-[var(--color-fill-1)]"
      >
        <template #title>
          <div class="flex flex-wrap items-center gap-2">
            <span>{{ item.label }}</span>
            <a-tag color="arcoblue">{{ t('admin.applications.tierPlatform') }}</a-tag>
          </div>
        </template>
        <p class="text-sm text-muted-foreground">{{ item.description }}</p>
        <p v-if="item.ruby_namespaces?.length" class="mt-2 font-mono text-xs text-muted-foreground">
          {{ item.ruby_namespaces.join(' · ') }}
        </p>
      </a-card>
    </div>
  </section>

  <section class="mb-8">
    <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-lg font-semibold">{{ t('admin.applications.appsTitle') }}</h2>
        <p class="text-sm text-muted-foreground">{{ t('admin.applications.appsHint') }}</p>
      </div>
      <Link
        :href="featureFlagsUrl"
        class="rounded border border-[var(--color-border-3)] px-3 py-1.5 text-sm text-[rgb(var(--primary-6))] no-underline transition-colors hover:bg-[var(--color-fill-2)]"
      >
        {{ t('admin.applications.manageToggles') }}
      </Link>
    </div>
    <div class="grid gap-3 md:grid-cols-2">
      <a-card
        v-for="item in applications"
        :key="item.id"
        :bordered="false"
        class="bg-[var(--color-fill-1)]"
      >
        <template #title>
          <div class="flex flex-wrap items-center gap-2">
            <span>{{ item.label }}</span>
            <a-tag :color="item.enabled ? 'green' : 'gray'">
              {{ item.enabled ? t('admin.ui.enabled') : t('admin.ui.disabled') }}
            </a-tag>
            <a-tag>{{ t('admin.applications.tierApplication') }}</a-tag>
          </div>
        </template>
        <p class="text-sm text-muted-foreground">{{ item.description }}</p>
        <p v-if="item.ruby_namespaces?.length" class="mt-2 font-mono text-xs text-muted-foreground">
          {{ item.ruby_namespaces.join(' · ') }}
        </p>
        <p v-if="item.path_prefixes?.length" class="mt-1 font-mono text-xs text-muted-foreground">
          {{ item.path_prefixes.join(', ') }}
        </p>
      </a-card>
    </div>
  </section>

  <section class="mb-8">
    <h2 class="mb-1 text-lg font-semibold">{{ t('admin.applications.pluginsTitle') }}</h2>
    <p class="mb-4 text-sm text-muted-foreground">{{ t('admin.applications.pluginsHint') }}</p>

    <div v-if="plugins.length" class="grid gap-3">
      <a-card
        v-for="plugin in plugins"
        :key="plugin.id"
        :bordered="false"
        class="bg-[var(--color-fill-1)]"
        hoverable
      >
        <template #title>
          <div class="flex flex-wrap items-center gap-2">
            <span>{{ plugin.name }}</span>
            <a-tag :color="pluginStatusColor(plugin.status)">
              {{ pluginStatusLabel(plugin.status) }}
            </a-tag>
            <a-tag>v{{ plugin.version }}</a-tag>
            <span class="font-mono text-xs font-normal text-muted-foreground">{{ plugin.id }}</span>
          </div>
        </template>

        <p v-if="plugin.description" class="text-sm text-muted-foreground">
          {{ plugin.description }}
        </p>
        <a-descriptions class="mt-3" :column="{ xs: 1, sm: 2, md: 3 }" size="small">
          <a-descriptions-item :label="t('admin.applications.pluginApiLabel')">
            v{{ plugin.api_version }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.pluginListenersLabel')">
            {{ plugin.listener_count }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.pluginFailuresLabel')">
            {{ plugin.failure_count }}
          </a-descriptions-item>
          <a-descriptions-item
            v-if="plugin.activation_order != null"
            :label="t('admin.applications.pluginActivationOrderLabel')"
          >
            {{ plugin.activation_order }}
          </a-descriptions-item>
          <a-descriptions-item v-if="plugin.author" :label="t('admin.applications.pluginAuthorLabel')">
            {{ plugin.author }}
          </a-descriptions-item>
        </a-descriptions>

        <div class="mt-3">
          <p class="text-xs font-medium">{{ t('admin.applications.pluginCapabilities') }}</p>
          <a-space v-if="plugin.capabilities.length" class="mt-1" wrap :size="[4, 4]">
            <a-tag v-for="capability in plugin.capabilities" :key="capability" bordered>
              {{ capability }}
            </a-tag>
          </a-space>
          <p v-else class="mt-1 text-xs text-muted-foreground">
            {{ t('admin.applications.pluginNoCapabilities') }}
          </p>
        </div>

        <div v-if="Object.keys(plugin.requires).length" class="mt-3">
          <p class="text-xs font-medium">{{ t('admin.applications.pluginDependencies') }}</p>
          <a-descriptions
            class="mt-1"
            :column="{ xs: 1, sm: 2 }"
            layout="vertical"
            :bordered="false"
          >
            <a-descriptions-item
              v-for="(requirement, dependency) in plugin.requires"
              :key="dependency"
              :label="dependency"
            >
              <span class="font-mono">{{ requirement }}</span>
            </a-descriptions-item>
          </a-descriptions>
        </div>

        <a-collapse
          v-if="plugin.contribution_descriptors.length"
          class="mt-3"
          :bordered="false"
        >
          <a-collapse-item>
            <template #header>
              {{
                t('admin.applications.contributions.header', {
                  count: plugin.contribution_count,
                })
              }}
            </template>
            <div class="grid gap-2 lg:grid-cols-2">
              <a-card
                v-for="contribution in plugin.contribution_descriptors"
                :key="contribution.id"
                size="small"
                :bordered="false"
                class="bg-[var(--color-fill-1)]"
              >
                <a-space wrap>
                  <a-tag color="arcoblue">
                    {{ contributionTypeLabel(contribution.type) }}
                  </a-tag>
                  <span class="font-mono text-xs">{{ contribution.id }}</span>
                </a-space>
                <p class="mt-2 break-words text-xs text-muted-foreground">
                  {{ contributionPayloadSummary(contribution.payload) }}
                </p>
                <a-space
                  v-if="contribution.before.length ||
                    contribution.after.length ||
                    contribution.requires.length ||
                    contribution.conflicts.length"
                  class="mt-2"
                  wrap
                  :size="[4, 4]"
                >
                  <a-tag v-for="item in contribution.requires" :key="`requires-${item}`">
                    {{ t('admin.applications.contributions.requires') }} · {{ item }}
                  </a-tag>
                  <a-tag v-for="item in contribution.before" :key="`before-${item}`">
                    {{ t('admin.applications.contributions.before') }} · {{ item }}
                  </a-tag>
                  <a-tag v-for="item in contribution.after" :key="`after-${item}`">
                    {{ t('admin.applications.contributions.after') }} · {{ item }}
                  </a-tag>
                  <a-tag
                    v-for="item in contribution.conflicts"
                    :key="`conflicts-${item}`"
                    color="red"
                  >
                    {{ t('admin.applications.contributions.conflicts') }} · {{ item }}
                  </a-tag>
                </a-space>
              </a-card>
            </div>
          </a-collapse-item>
        </a-collapse>

        <p v-if="plugin.homepage" class="mt-3 break-all font-mono text-xs text-muted-foreground">
          {{ plugin.homepage }}
        </p>
        <a-alert
          v-if="plugin.last_error"
          class="mt-3"
          type="error"
          :title="t('admin.applications.pluginLastError')"
        >
          {{ plugin.last_error }}
        </a-alert>
      </a-card>
    </div>
    <a-empty v-else :description="t('admin.applications.noPlugins')" />
  </section>

  <section v-if="pluginDiagnostics.length" class="mb-8">
    <h2 class="mb-1 text-lg font-semibold">{{ t('admin.applications.diagnosticsTitle') }}</h2>
    <p class="mb-4 text-sm text-muted-foreground">{{ t('admin.applications.diagnosticsHint') }}</p>
    <div class="overflow-x-auto">
      <a-table
        :data="pluginDiagnostics"
        :pagination="false"
        :bordered="false"
        :scroll="{ minWidth: 920 }"
      >
        <template #columns>
          <a-table-column :title="t('admin.applications.diagnosticLevel')" data-index="level" :width="110">
            <template #cell="{ record }">
              <a-tag :color="diagnosticColor(record.level)">{{ record.level }}</a-tag>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.applications.diagnosticContext')" :width="240">
            <template #cell="{ record }">
              <div class="space-y-1">
                <p class="font-mono text-xs font-medium">{{ record.code }}</p>
                <p class="font-mono text-xs text-muted-foreground">
                  {{ [record.phase, record.plugin_id, record.event].filter(Boolean).join(' · ') }}
                </p>
              </div>
            </template>
          </a-table-column>
          <a-table-column :title="t('admin.applications.diagnosticMessage')">
            <template #cell="{ record }">
              <p class="break-words">{{ record.message }}</p>
              <p v-if="record.exception" class="mt-1 font-mono text-xs text-muted-foreground">
                {{ record.exception }}
              </p>
            </template>
          </a-table-column>
          <a-table-column
            :title="t('admin.applications.diagnosticTime')"
            data-index="occurred_at"
            :width="210"
          />
        </template>
      </a-table>
    </div>
  </section>

  <section>
    <h2 class="mb-1 text-lg font-semibold">{{ t('admin.applications.extensionsTitle') }}</h2>
    <p class="mb-4 text-sm text-muted-foreground">{{ t('admin.applications.extensionsHint') }}</p>
    <div class="grid gap-3">
      <a-card
        v-for="item in extensions"
        :key="item.id"
        :bordered="false"
        class="bg-[var(--color-fill-1)]"
      >
        <template #title>
          <div class="flex flex-wrap items-center gap-2">
            <span>{{ item.label }}</span>
            <a-tag>{{ t('admin.applications.tierExtension') }}</a-tag>
            <span v-if="item.kind" class="text-xs font-normal text-muted-foreground">{{ item.kind }}</span>
          </div>
        </template>
        <p class="text-sm text-muted-foreground">{{ item.description }}</p>
        <p v-if="item.host" class="mt-2 font-mono text-xs text-muted-foreground">{{ item.host }}</p>
        <a-space v-if="item.capabilities?.length" class="mt-2" wrap :size="[4, 4]">
          <a-tag v-for="capability in item.capabilities" :key="capability" bordered>
            {{ capability }}
          </a-tag>
        </a-space>
        <ul v-if="item.limitations?.length" class="mt-2 list-inside list-disc text-xs text-muted-foreground">
          <li v-for="(line, index) in item.limitations" :key="index">{{ line }}</li>
        </ul>
      </a-card>
    </div>
  </section>

  <Drawer
    :visible="Boolean(selectedCatalogRelease)"
    :width="'min(760px, calc(100vw - 24px))'"
    :title="t('admin.applications.catalog.detailTitle')"
    unmount-on-close
    @cancel="selectedCatalogRelease = null"
  >
    <a-space v-if="selectedCatalogRelease" direction="vertical" :size="20" fill>
      <a-descriptions :column="1" bordered size="small">
        <a-descriptions-item :label="t('admin.applications.catalog.plugin')">
          {{ selectedCatalogRelease.plugin_id }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.catalog.releaseIdentity')">
          {{ selectedCatalogRelease.version }} · API {{ selectedCatalogRelease.api_version }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.catalog.manifestDigest')">
          <span class="break-all font-mono text-xs">
            {{ selectedCatalogRelease.manifest_sha256 }}
          </span>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.catalog.packageDigest')">
          <a-space direction="vertical" size="mini">
            <span class="break-all font-mono text-xs">
              {{ selectedCatalogRelease.package_sha256 }}
            </span>
            <a-tag
              :color="selectedCatalogRelease.package_digest_source === 'receipt'
                ? 'green'
                : 'orange'"
            >
              {{
                t(
                  `admin.applications.catalog.digestSources.${selectedCatalogRelease.package_digest_source}`,
                )
              }}
            </a-tag>
          </a-space>
        </a-descriptions-item>
      </a-descriptions>

      <a-space
        v-if="selectedCatalogRelease.diagnostics.length"
        direction="vertical"
        fill
      >
        <a-alert
          v-for="diagnostic in selectedCatalogRelease.diagnostics"
          :key="diagnostic.code"
          :type="diagnostic.severity === 'error' ? 'error' : 'warning'"
          show-icon
          :title="t(`admin.applications.catalog.findings.${diagnostic.code}`)"
        />
      </a-space>

      <div>
        <h3 class="mb-3 text-base font-semibold">
          {{ t('admin.applications.catalog.contributionsTitle') }}
        </h3>
        <a-table
          :data="selectedCatalogRelease.contributions"
          :pagination="{ pageSize: 8, hideOnSinglePage: true }"
          :bordered="false"
          :scroll="{ minWidth: 660 }"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.catalog.contributionId')"
              data-index="id"
            />
            <a-table-column
              :title="t('admin.applications.catalog.contributionType')"
              :width="150"
            >
              <template #cell="{ record }">
                {{ contributionTypeLabel(record.type) }}
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.catalog.schemaDigest')"
              :width="170"
            >
              <template #cell="{ record }">
                <span class="font-mono text-xs">
                  {{ record.schema_sha256?.slice(0, 16) || '—' }}
                </span>
              </template>
            </a-table-column>
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.catalog.noContributions')" />
          </template>
        </a-table>
      </div>

      <div>
        <h3 class="mb-3 text-base font-semibold">
          {{ t('admin.applications.catalog.fileIssuesTitle') }}
        </h3>
        <a-table
          :data="selectedCatalogRelease.file_issues"
          :pagination="{ pageSize: 8, hideOnSinglePage: true }"
          :bordered="false"
          :scroll="{ minWidth: 620 }"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.catalog.filePath')"
              data-index="path"
            />
            <a-table-column
              :title="t('admin.applications.catalog.health')"
              :width="150"
            >
              <template #cell="{ record }">
                <a-tag :color="marketplaceStatusColor(record.health)">
                  {{ marketplaceStatusLabel(record.health) }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column
              :title="t('admin.applications.catalog.fileSize')"
              :width="150"
            >
              <template #cell="{ record }">
                {{ record.expected_size }} → {{ record.observed_size ?? '—' }}
              </template>
            </a-table-column>
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.catalog.noFileIssues')" />
          </template>
        </a-table>
      </div>
    </a-space>
  </Drawer>

  <Drawer
    :visible="Boolean(selectedLifecycleRun)"
    :width="'min(680px, calc(100vw - 24px))'"
    :title="t('admin.applications.lifecycle.detailTitle')"
    unmount-on-close
    @cancel="selectedLifecycleRun = null"
  >
    <a-space v-if="selectedLifecycleRun" direction="vertical" :size="20" fill>
      <a-descriptions :column="1" bordered size="small">
        <a-descriptions-item :label="t('admin.applications.lifecycle.plugin')">
          {{ selectedLifecycleRun.plugin_id || '—' }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.operation')">
          <span class="break-all font-mono text-xs">
            {{ selectedLifecycleRun.operation_id }}
          </span>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.action')">
          {{ t(`admin.applications.generations.actions.${selectedLifecycleRun.action}`) }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.actor')">
          {{ selectedLifecycleRun.actor || t('admin.applications.lifecycle.systemActor') }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.runState')">
          <a-tag :color="lifecycleStatusColor(selectedLifecycleRun.state)">
            {{ lifecycleLabel(selectedLifecycleRun.state) }}
          </a-tag>
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.versionChange')">
          {{ selectedLifecycleRun.from_version || '—' }}
          →
          {{ selectedLifecycleRun.to_version || '—' }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.generation')">
          {{ selectedLifecycleRun.generation_number || '—' }}
        </a-descriptions-item>
        <a-descriptions-item :label="t('admin.applications.lifecycle.executionMode')">
          <a-space wrap>
            <a-tag v-if="selectedLifecycleRun.dry_run" color="arcoblue">
              {{ t('admin.applications.marketplace.dryRun') }}
            </a-tag>
            <a-tag v-if="selectedLifecycleRun.maintenance_mode" color="orange">
              {{ t('admin.applications.marketplace.maintenanceMode') }}
            </a-tag>
            <span
              v-if="!selectedLifecycleRun.dry_run &&
                !selectedLifecycleRun.maintenance_mode"
            >
              {{ t('admin.applications.lifecycle.standardMode') }}
            </span>
          </a-space>
        </a-descriptions-item>
      </a-descriptions>

      <a-alert
        v-if="selectedLifecycleRun.error_code || selectedLifecycleRun.error_message"
        type="error"
        show-icon
        :title="t('admin.applications.lifecycle.failed')"
      >
        {{ selectedLifecycleRun.error_message }}
      </a-alert>

      <div>
        <h3 class="mb-3 text-base font-semibold">
          {{ t('admin.applications.lifecycle.stepsTitle') }}
        </h3>
        <Timeline v-if="selectedLifecycleRun.steps.length">
          <TimelineItem
            v-for="step in selectedLifecycleRun.steps"
            :key="`${selectedLifecycleRun.operation_id}-${step.sequence}`"
            :label="step.completed_at || step.started_at"
          >
            <a-space direction="vertical" size="mini">
              <strong>{{ t(`admin.applications.lifecycle.steps.${step.step_key}`) }}</strong>
              <a-tag :color="lifecycleStatusColor(step.state)">
                {{ lifecycleLabel(step.state) }}
              </a-tag>
              <span
                v-if="step.error_message"
                class="text-sm text-[rgb(var(--danger-6))]"
              >
                {{ step.error_message }}
              </span>
            </a-space>
          </TimelineItem>
        </Timeline>
        <a-empty
          v-else
          :description="t('admin.applications.lifecycle.noSteps')"
        />
      </div>
    </a-space>
  </Drawer>

  <a-modal
    v-model:visible="uninstallModalVisible"
    :title="t('admin.applications.marketplace.uninstallConfirmTitle')"
    :footer="false"
    :mask-closable="!uninstallSubmitting"
    :esc-to-close="!uninstallSubmitting"
    :width="'min(620px, calc(100vw - 32px))'"
  >
    <a-alert
      :type="uninstallDataMode === 'purge_data' ? 'error' : 'warning'"
      show-icon
      :closable="false"
      :title="t(`admin.applications.marketplace.dataModes.${uninstallDataMode}.warningTitle`)"
      class="mb-5"
    >
      {{
        t(`admin.applications.marketplace.dataModes.${uninstallDataMode}.warning`, {
          plugin: uninstallTarget?.name || uninstallTarget?.id,
        })
      }}
    </a-alert>

    <a-descriptions
      v-if="uninstallTarget"
      class="mb-4"
      :column="{ xs: 1, sm: 2 }"
      layout="vertical"
      :bordered="false"
      size="small"
    >
      <a-descriptions-item :label="t('admin.applications.marketplace.version')">
        {{ uninstallTarget.version }}
      </a-descriptions-item>
      <a-descriptions-item :label="t('admin.applications.marketplace.checksum')">
        <span class="break-all font-mono text-xs">{{ uninstallTarget.sha256 }}</span>
      </a-descriptions-item>
    </a-descriptions>

    <a-form
      :model="{ confirmation: uninstallConfirmation, data_mode: uninstallDataMode }"
      layout="vertical"
    >
      <a-form-item
        field="data_mode"
        :label="t('admin.applications.marketplace.uninstallDataModeLabel')"
        required
      >
        <a-radio-group
          v-model="uninstallDataMode"
          direction="vertical"
          :disabled="uninstallSubmitting"
        >
          <a-radio
            v-if="pluginCapabilities.uninstall_preserve"
            value="preserve_data"
          >
            <div>
              <strong>
                {{ t('admin.applications.marketplace.dataModes.preserve_data.label') }}
              </strong>
              <p class="mt-1 text-xs text-muted-foreground">
                {{ t('admin.applications.marketplace.dataModes.preserve_data.description') }}
              </p>
            </div>
          </a-radio>
          <a-radio
            v-if="pluginCapabilities.uninstall_purge"
            value="purge_data"
          >
            <div>
              <strong>
                {{ t('admin.applications.marketplace.dataModes.purge_data.label') }}
              </strong>
              <p class="mt-1 text-xs text-muted-foreground">
                {{ t('admin.applications.marketplace.dataModes.purge_data.description') }}
              </p>
            </div>
          </a-radio>
        </a-radio-group>
      </a-form-item>
      <a-form-item
        field="confirmation"
        :label="t('admin.applications.marketplace.uninstallConfirmationLabel')"
        required
      >
        <a-input
          v-model="uninstallConfirmation"
          :placeholder="uninstallTarget?.id"
          :disabled="uninstallSubmitting"
          autocomplete="off"
        />
        <template #extra>
          {{
            t('admin.applications.marketplace.uninstallConfirmationHint', {
              plugin: uninstallTarget?.id,
            })
          }}
        </template>
      </a-form-item>
    </a-form>

    <div class="flex flex-wrap justify-end gap-2 pt-2">
      <a-button :disabled="uninstallSubmitting" @click="closeUninstall">
        {{ t('admin.ui.cancel') }}
      </a-button>
      <a-button
        type="primary"
        status="danger"
        :loading="uninstallSubmitting"
        :disabled="!canUninstall"
        @click="submitUninstall"
      >
        {{ lifecycleActionLabel('uninstall') }}
      </a-button>
    </div>
  </a-modal>
</template>
