<script setup lang="ts">
import { router, useForm } from '@inertiajs/vue3'
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

const props = withDefaults(defineProps<{
  title: string
  platform: CatalogItem[]
  applications: CatalogItem[]
  extensions: CatalogItem[]
  plugins?: PluginItem[]
  pluginDiagnostics?: PluginDiagnostic[]
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
}>(), {
  plugins: () => [],
  pluginDiagnostics: () => [],
})

const pluginFiles = ref<FileItem[]>([])
const selectedLifecycleRun = ref<PluginLifecycleRun | null>(null)
const selectedCatalogRelease = ref<PluginCatalogRelease | null>(null)
const uninstallTarget = ref<MarketplacePlugin | null>(null)
const uninstallConfirmation = ref('')
const uninstallSubmitting = ref(false)
const uninstallDataMode = ref<'preserve_data' | 'purge_data'>('preserve_data')
const canMutatePlugins = computed(() =>
  props.pluginCapabilities.install ||
  props.pluginCapabilities.enable ||
  props.pluginCapabilities.disable ||
  props.pluginCapabilities.recover ||
  props.pluginCapabilities.rollback ||
  props.pluginCapabilities.uninstall_preserve ||
  props.pluginCapabilities.uninstall_purge,
)
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
  <a-space direction="vertical" :size="16" fill>
    <a-card :bordered="true" size="small">
      <a-row :gutter="[16, 12]" align="center">
        <a-col :xs="24" :lg="17">
          <a-page-header
            :title="title"
            :subtitle="t('admin.applications.subtitle')"
            :show-back="false"
          >
          </a-page-header>
        </a-col>
        <a-col :xs="24" :lg="7">
          <a-row justify="end">
            <a-button type="outline" :href="featureFlagsUrl">
              <template #icon><IconSettings /></template>
              {{ t('admin.applications.manageToggles') }}
            </a-button>
          </a-row>
        </a-col>
      </a-row>
    </a-card>

    <a-grid
      :cols="24"
      :col-gap="{ xs: 0, sm: 12 }"
      :row-gap="12"
      align="stretch"
    >
      <a-grid-item :span="{ xs: 24, xl: 18 }">
        <a-alert
          type="warning"
          show-icon
          :title="t('admin.applications.trustedPluginWarning')"
        >
          <a-space direction="vertical" size="mini" fill>
            <a-typography-text v-if="!freelyExtensible">
              {{ t('admin.applications.notFreelyExtensible') }}
            </a-typography-text>
            <a-typography-text type="secondary">
              {{ t('admin.applications.readDocs') }}
            </a-typography-text>
          </a-space>
        </a-alert>
      </a-grid-item>
      <a-grid-item :span="{ xs: 24, xl: 6 }">
        <a-card size="small" :bordered="true">
          <a-statistic :title="t('admin.applications.pluginsTitle')" :value="plugins.length">
            <template #prefix><IconApps /></template>
          </a-statistic>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card :bordered="true">
      <a-tabs default-active-key="applications" type="line">
      <a-tab-pane key="platform" :title="t('admin.applications.platformTitle')">
        <a-space direction="vertical" :size="16" fill>
          <a-typography-paragraph type="secondary">
            {{ t('admin.applications.platformHint') }}
          </a-typography-paragraph>
          <a-grid :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
            <a-grid-item v-for="item in platform" :key="item.id">
              <a-card :bordered="true" hoverable>
                <template #title>
                  <a-space wrap>
                    <a-typography-text bold>{{ item.label }}</a-typography-text>
                    <a-tag color="arcoblue">{{ t('admin.applications.tierPlatform') }}</a-tag>
                  </a-space>
                </template>
                <a-space direction="vertical" :size="16" fill>
                  <a-typography-paragraph>{{ item.description }}</a-typography-paragraph>
                  <a-descriptions
                    v-if="item.ruby_namespaces?.length"
                    :column="1"
                    bordered
                    size="small"
                  >
                    <a-descriptions-item :label="t('admin.applications.namespacesLabel')">
                      <a-space wrap size="mini">
                        <a-tag
                          v-for="namespace in item.ruby_namespaces"
                          :key="namespace"
                          bordered
                        >
                          {{ namespace }}
                        </a-tag>
                      </a-space>
                    </a-descriptions-item>
                  </a-descriptions>
                </a-space>
              </a-card>
            </a-grid-item>
          </a-grid>
        </a-space>
      </a-tab-pane>

      <a-tab-pane key="applications" :title="t('admin.applications.appsTitle')">
        <a-space direction="vertical" :size="16" fill>
          <a-typography-paragraph type="secondary">
            {{ t('admin.applications.appsHint') }}
          </a-typography-paragraph>
          <a-grid :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
            <a-grid-item v-for="item in applications" :key="item.id">
              <a-card :bordered="true" hoverable>
                <template #title>
                  <a-space wrap>
                    <a-typography-text bold>{{ item.label }}</a-typography-text>
                    <a-tag :color="item.enabled ? 'green' : 'gray'">
                      {{ item.enabled ? t('admin.ui.enabled') : t('admin.ui.disabled') }}
                    </a-tag>
                    <a-tag>{{ t('admin.applications.tierApplication') }}</a-tag>
                  </a-space>
                </template>
                <a-space direction="vertical" :size="16" fill>
                  <a-typography-paragraph>{{ item.description }}</a-typography-paragraph>
                  <a-descriptions
                    v-if="item.ruby_namespaces?.length || item.path_prefixes?.length"
                    :column="{ xs: 1, md: 2 }"
                    bordered
                    size="small"
                  >
                    <a-descriptions-item
                      v-if="item.ruby_namespaces?.length"
                      :label="t('admin.applications.namespacesLabel')"
                    >
                      <a-space wrap size="mini">
                        <a-tag
                          v-for="namespace in item.ruby_namespaces"
                          :key="namespace"
                          bordered
                        >
                          {{ namespace }}
                        </a-tag>
                      </a-space>
                    </a-descriptions-item>
                    <a-descriptions-item
                      v-if="item.path_prefixes?.length"
                      :label="t('admin.applications.routesLabel')"
                    >
                      <a-space wrap size="mini">
                        <a-tag v-for="prefix in item.path_prefixes" :key="prefix" bordered>
                          {{ prefix }}
                        </a-tag>
                      </a-space>
                    </a-descriptions-item>
                  </a-descriptions>
                </a-space>
              </a-card>
            </a-grid-item>
          </a-grid>
        </a-space>
      </a-tab-pane>

      <a-tab-pane key="plugins" :title="t('admin.applications.pluginsTitle')">
        <a-space direction="vertical" :size="16" fill>
          <a-divider orientation="left">
            <a-space align="center" wrap>
              <a-typography-text bold>
                {{ t('admin.applications.marketplace.title') }}
              </a-typography-text>
              <a-tag color="arcoblue" round>
                {{ t('admin.applications.pluginsTitle') }}
              </a-tag>
            </a-space>
          </a-divider>
          <a-typography-paragraph type="secondary">
            {{ t('admin.applications.marketplace.hint') }}
          </a-typography-paragraph>

          <a-card v-if="canMutatePlugins" :bordered="true">
            <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="8">
              <a-grid-item>
                <a-checkbox v-model="installForm.dry_run">
                  {{ t('admin.applications.marketplace.dryRun') }}
                </a-checkbox>
              </a-grid-item>
              <a-grid-item>
                <a-checkbox v-model="installForm.maintenance_mode">
                  {{ t('admin.applications.marketplace.maintenanceMode') }}
                </a-checkbox>
              </a-grid-item>
            </a-grid>
          </a-card>

          <a-alert
            v-for="error in pluginMarketplace.errors"
            :key="`${error.code}-${error.message}`"
            type="warning"
            show-icon
            :title="t('admin.applications.marketplace.errorsTitle')"
          >
            {{ error.message }}
          </a-alert>

          <a-row :gutter="[16, 16]">
            <a-col v-if="pluginCapabilities.install" :xs="24" :xl="10">
              <a-card
                :title="t('admin.applications.marketplace.installTitle')"
                :bordered="true"
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
            </a-col>

            <a-col :xs="24" :xl="pluginCapabilities.install ? 14 : 24">
              <a-card
                :title="t('admin.applications.marketplace.managedTitle')"
                :bordered="true"
              >
                <a-list
                  v-if="pluginMarketplace.plugins.length"
                  :bordered="false"
                  size="small"
                  :max-height="620"
                  scrollbar
                >
                  <a-list-item
                    v-for="plugin in pluginMarketplace.plugins"
                    :key="plugin.id"
                  >
                    <a-space direction="vertical" :size="12" fill>
                      <a-list-item-meta
                        :title="plugin.name"
                        :description="plugin.id"
                      />
                      <a-space wrap size="small">
                        <a-tag :color="marketplaceStatusColor(plugin.status)">
                          {{ marketplaceStatusLabel(plugin.status) }}
                        </a-tag>
                        <a-tag>v{{ plugin.version }}</a-tag>
                        <a-tag v-if="plugin.recoverable" color="orange">
                          {{ t('admin.applications.marketplace.recoverable') }}
                        </a-tag>
                      </a-space>
                      <a-descriptions
                        :column="{ xs: 1, md: 2 }"
                        size="small"
                        bordered
                      >
                        <a-descriptions-item
                          :label="t('admin.applications.marketplace.filesystemStatus')"
                        >
                          {{ marketplaceStatusLabel(plugin.filesystem_status) }}
                        </a-descriptions-item>
                        <a-descriptions-item
                          :label="t('admin.applications.marketplace.runtimeStatus')"
                        >
                          {{ marketplaceStatusLabel(plugin.runtime_status) }}
                        </a-descriptions-item>
                        <a-descriptions-item
                          v-if="plugin.sha256"
                          :label="t('admin.applications.marketplace.checksum')"
                        >
                          <a-typography-text
                            code
                            copyable
                            :ellipsis="{ showTooltip: true }"
                          >
                            {{ plugin.sha256 }}
                          </a-typography-text>
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
                        <a-descriptions-item
                          :label="t('admin.applications.marketplace.fileHealth')"
                        >
                          {{
                            t('admin.applications.marketplace.fileHealthSummary', {
                              status: marketplaceStatusLabel(plugin.health.status),
                              expected: plugin.health.expected_count,
                              actual: plugin.health.actual_count,
                              missing: plugin.health.missing_count,
                              modified: plugin.health.modified_count,
                              unknown: plugin.health.unknown_count,
                            })
                          }}
                        </a-descriptions-item>
                      </a-descriptions>
                      <a-space v-if="canManagePlugins" wrap size="small">
                        <a-button
                          v-if="pluginCapabilities.enable && plugin.filesystem_status === 'disabled'"
                          size="small"
                          @click="changePluginState('enable', plugin.id)"
                        >
                          {{ lifecycleActionLabel('enable') }}
                        </a-button>
                        <a-button
                          v-if="pluginCapabilities.disable && plugin.filesystem_status === 'installed'"
                          size="small"
                          @click="changePluginState('disable', plugin.id)"
                        >
                          {{ lifecycleActionLabel('disable') }}
                        </a-button>
                        <a-button
                          v-if="pluginCapabilities.diagnostics"
                          size="small"
                          @click="checkPluginHealth(plugin.id)"
                        >
                          {{ t('admin.applications.marketplace.checkHealth') }}
                        </a-button>
                        <a-button
                          v-if="pluginCapabilities.recover && plugin.recoverable && hasVerifiedUninstallIdentity(plugin)"
                          size="small"
                          status="warning"
                          @click="recoverPlugin(plugin)"
                        >
                          {{ lifecycleActionLabel('recover') }}
                        </a-button>
                        <a-button
                          v-if="pluginCapabilities.rollback && plugin.rollback_available && hasVerifiedUninstallIdentity(plugin)"
                          size="small"
                          status="warning"
                          @click="rollbackPlugin(plugin)"
                        >
                          {{ lifecycleActionLabel('rollback') }}
                        </a-button>
                        <a-button
                          v-if="(pluginCapabilities.uninstall_preserve || pluginCapabilities.uninstall_purge) &&
                            ['installed', 'disabled'].includes(plugin.filesystem_status) &&
                            hasVerifiedUninstallIdentity(plugin)"
                          size="small"
                          status="danger"
                          @click="openUninstall(plugin)"
                        >
                          {{ lifecycleActionLabel('uninstall') }}
                        </a-button>
                      </a-space>
                    </a-space>
                  </a-list-item>
                </a-list>
                <a-empty
                  v-else
                  :description="t('admin.applications.marketplace.noManagedPlugins')"
                />
              </a-card>
            </a-col>
          </a-row>

          <a-card
            :title="t('admin.applications.marketplace.operationsTitle')"
            :bordered="true"
          >
            <a-table
              :data="pluginMarketplace.operations"
              :pagination="false"
              :bordered="{ cell: true }"
              :scroll="{ x: 960 }"
              size="small"
              stripe
            >
              <template #columns>
                <a-table-column
                  :title="t('admin.applications.marketplace.action')"
                  data-index="action"
                  :width="130"
                  ellipsis
                  tooltip
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
                  ellipsis
                  tooltip
                />
                <a-table-column
                  :title="t('admin.applications.marketplace.version')"
                  data-index="version"
                  :width="120"
                />
                <a-table-column
                  :title="t('admin.applications.marketplace.message')"
                  data-index="message"
                  :width="280"
                  ellipsis
                  tooltip
                />
                <a-table-column
                  :title="t('admin.applications.marketplace.time')"
                  data-index="occurred_at"
                  :width="210"
                  ellipsis
                  tooltip
                />
              </template>
              <template #empty>
                <a-empty :description="t('admin.applications.marketplace.noOperations')" />
              </template>
            </a-table>
          </a-card>

          <a-divider orientation="left">
            <a-typography-text bold>
              {{ t('admin.applications.marketplace.runtimeTitle') }}
            </a-typography-text>
          </a-divider>
          <a-typography-paragraph type="secondary">
            {{ t('admin.applications.pluginsHint') }}
          </a-typography-paragraph>
          <a-collapse v-if="plugins.length" accordion>
            <a-collapse-item
              v-for="plugin in plugins"
              :key="plugin.id"
              :name="plugin.id"
            >
              <template #header>
                <a-typography-text bold>{{ plugin.name }}</a-typography-text>
              </template>
              <template #extra>
                <a-tag :color="pluginStatusColor(plugin.status)">
                  {{ pluginStatusLabel(plugin.status) }}
                </a-tag>
              </template>

              <a-space direction="vertical" :size="16" fill>
                <a-typography-paragraph v-if="plugin.description">
                  {{ plugin.description }}
                </a-typography-paragraph>
                <a-descriptions
                  :column="{ xs: 1, sm: 2, lg: 3 }"
                  size="small"
                  bordered
                >
                  <a-descriptions-item :label="t('admin.applications.pluginIdLabel')">
                    {{ plugin.id }}
                  </a-descriptions-item>
                  <a-descriptions-item :label="t('admin.applications.pluginVersionLabel')">
                    v{{ plugin.version }}
                  </a-descriptions-item>
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
                  <a-descriptions-item
                    v-if="plugin.author"
                    :label="t('admin.applications.pluginAuthorLabel')"
                  >
                    {{ plugin.author }}
                  </a-descriptions-item>
                  <a-descriptions-item
                    v-if="plugin.homepage"
                    :label="t('admin.applications.pluginHomepageLabel')"
                  >
                    <a-link
                      :href="plugin.homepage"
                      target="_blank"
                      rel="noopener"
                      data-admin-hard-navigation
                    >
                      {{ plugin.homepage }}
                    </a-link>
                  </a-descriptions-item>
                </a-descriptions>

                <a-space direction="vertical" size="mini" fill>
                  <a-typography-text bold>
                    {{ t('admin.applications.pluginCapabilities') }}
                  </a-typography-text>
                  <a-space v-if="plugin.capabilities?.length" wrap size="mini">
                    <a-tag
                      v-for="capability in plugin.capabilities || []"
                      :key="capability"
                      bordered
                    >
                      {{ capability }}
                    </a-tag>
                  </a-space>
                  <a-typography-text v-else type="secondary">
                    {{ t('admin.applications.pluginNoCapabilities') }}
                  </a-typography-text>
                </a-space>

                <a-descriptions
                  v-if="Object.keys(plugin.requires || {}).length"
                  :title="t('admin.applications.pluginDependencies')"
                  :column="1"
                  size="small"
                  bordered
                >
                  <a-descriptions-item
                    v-for="(requirement, dependency) in plugin.requires || {}"
                    :key="dependency"
                    :label="dependency"
                  >
                    {{ requirement }}
                  </a-descriptions-item>
                </a-descriptions>

                <a-collapse v-if="plugin.contribution_descriptors.length" accordion>
                  <a-collapse-item
                    name="contributions"
                    :header="t('admin.applications.contributions.header', {
                      count: plugin.contribution_count,
                    })"
                  >
                    <a-list :bordered="false" size="small">
                      <a-list-item
                        v-for="contribution in plugin.contribution_descriptors"
                        :key="contribution.id"
                      >
                        <a-space direction="vertical" size="mini" fill>
                          <a-space wrap size="mini">
                            <a-tag color="arcoblue">
                              {{ contributionTypeLabel(contribution.type) }}
                            </a-tag>
                            <a-typography-text code>{{ contribution.id }}</a-typography-text>
                            <a-tag bordered>{{ contribution.priority }}</a-tag>
                          </a-space>
                          <a-typography-text type="secondary">
                            {{ contributionPayloadSummary(contribution.payload) }}
                          </a-typography-text>
                          <a-space v-if="contribution.requires.length" wrap size="mini">
                            <a-tag v-for="item in contribution.requires" :key="item" bordered>
                              {{ t('admin.applications.contributions.requires') }} · {{ item }}
                            </a-tag>
                          </a-space>
                          <a-space v-if="contribution.before.length" wrap size="mini">
                            <a-tag v-for="item in contribution.before" :key="item" bordered>
                              {{ t('admin.applications.contributions.before') }} · {{ item }}
                            </a-tag>
                          </a-space>
                          <a-space v-if="contribution.after.length" wrap size="mini">
                            <a-tag v-for="item in contribution.after" :key="item" bordered>
                              {{ t('admin.applications.contributions.after') }} · {{ item }}
                            </a-tag>
                          </a-space>
                          <a-space v-if="contribution.conflicts.length" wrap size="mini">
                            <a-tag
                              v-for="item in contribution.conflicts"
                              :key="item"
                              color="red"
                            >
                              {{ t('admin.applications.contributions.conflicts') }} · {{ item }}
                            </a-tag>
                          </a-space>
                        </a-space>
                      </a-list-item>
                    </a-list>
                  </a-collapse-item>
                </a-collapse>

                <a-alert
                  v-if="plugin.last_error"
                  type="error"
                  :title="t('admin.applications.pluginLastError')"
                  show-icon
                >
                  {{ plugin.last_error }}
                </a-alert>
              </a-space>
            </a-collapse-item>
          </a-collapse>
          <a-empty v-else :description="t('admin.applications.noPlugins')" />
        </a-space>
      </a-tab-pane>

      <a-tab-pane key="diagnostics" :title="t('admin.applications.diagnosticsTitle')">
        <a-space direction="vertical" :size="16" fill>
          <a-typography-paragraph type="secondary">
            {{ t('admin.applications.diagnosticsHint') }}
          </a-typography-paragraph>
          <a-table
            :data="pluginDiagnostics"
            :pagination="false"
            :bordered="{ cell: true }"
            :scroll="{ x: 920 }"
            size="small"
            stripe
          >
            <template #columns>
              <a-table-column
                :title="t('admin.applications.diagnosticLevel')"
                data-index="level"
                :width="110"
              >
                <template #cell="{ record }">
                  <a-tag :color="diagnosticColor(record.level)">{{ record.level }}</a-tag>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.applications.diagnosticContext')"
                :width="260"
                ellipsis
                tooltip
              >
                <template #cell="{ record }">
                  <a-space direction="vertical" size="mini" fill>
                    <a-typography-text code>{{ record.code }}</a-typography-text>
                    <a-typography-text type="secondary">
                      {{ [record.phase, record.plugin_id, record.event].filter(Boolean).join(' · ') }}
                    </a-typography-text>
                  </a-space>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.applications.diagnosticMessage')"
                :width="360"
              >
                <template #cell="{ record }">
                  <a-space direction="vertical" size="mini" fill>
                    <a-typography-text :ellipsis="{ showTooltip: true }">
                      {{ record.message }}
                    </a-typography-text>
                    <a-typography-text
                      v-if="record.exception"
                      type="secondary"
                      code
                      :ellipsis="{ showTooltip: true }"
                    >
                      {{ record.exception }}
                    </a-typography-text>
                  </a-space>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.applications.diagnosticTime')"
                data-index="occurred_at"
                :width="210"
                ellipsis
                tooltip
              />
            </template>
            <template #empty>
              <a-empty :description="t('admin.applications.noDiagnostics')" />
            </template>
          </a-table>

          <a-card
            v-if="pluginCapabilities.diagnostics"
            :title="t('admin.applications.catalog.title')"
            :bordered="true"
          >
            <template #extra>
              <a-button type="primary" @click="reconcilePluginCatalog">
                {{ t('admin.applications.catalog.reconcile') }}
              </a-button>
            </template>
            <a-alert
              v-if="!pluginCatalog.available"
              type="warning"
              :title="t('admin.applications.catalog.unavailable')"
              show-icon
            />
            <a-table
              v-else
              :data="pluginCatalog.releases"
              :pagination="{ pageSize: 12 }"
              :bordered="{ cell: true }"
              :scroll="{ x: 980 }"
              row-key="id"
              size="small"
              stripe
            >
              <template #columns>
                <a-table-column
                  :title="t('admin.applications.catalog.plugin')"
                  data-index="plugin_id"
                  :width="180"
                  ellipsis
                  tooltip
                />
                <a-table-column
                  :title="t('admin.applications.catalog.version')"
                  data-index="version"
                  :width="120"
                />
                <a-table-column :title="t('admin.applications.catalog.state')" :width="140">
                  <template #cell="{ record }">
                    <a-tag :color="marketplaceStatusColor(record.state)">
                      {{ marketplaceStatusLabel(record.state) }}
                    </a-tag>
                  </template>
                </a-table-column>
                <a-table-column :title="t('admin.applications.catalog.health')" :width="140">
                  <template #cell="{ record }">
                    <a-tag :color="marketplaceStatusColor(record.health)">
                      {{ marketplaceStatusLabel(record.health) }}
                    </a-tag>
                  </template>
                </a-table-column>
                <a-table-column :title="t('admin.applications.catalog.contents')" :width="220">
                  <template #cell="{ record }">
                    {{
                      t('admin.applications.catalog.contentCounts', {
                        files: record.file_count,
                        contributions: record.contributions.length,
                        findings: record.diagnostics.length,
                      })
                    }}
                  </template>
                </a-table-column>
                <a-table-column
                  :title="t('admin.applications.catalog.observedAt')"
                  data-index="observed_at"
                  :width="190"
                />
                <a-table-column :title="t('admin.applications.catalog.details')" :width="100">
                  <template #cell="{ record }">
                    <a-button size="small" @click="selectedCatalogRelease = record">
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

          <a-card
            v-if="pluginCapabilities.diagnostics"
            :title="t('admin.applications.lifecycle.title')"
            :bordered="true"
          >
            <a-alert
              v-if="!pluginLifecycle.available"
              type="warning"
              :title="t('admin.applications.lifecycle.unavailable')"
              show-icon
            />
            <a-grid v-else :cols="{ xs: 1, xl: 2 }" :col-gap="16" :row-gap="16">
              <a-grid-item>
                <a-table
                  :data="pluginLifecycle.installations"
                  :pagination="{ pageSize: 10 }"
                  :bordered="{ cell: true }"
                  :scroll="{ x: 720 }"
                  row-key="plugin_id"
                  size="small"
                >
                  <template #columns>
                    <a-table-column
                      :title="t('admin.applications.lifecycle.plugin')"
                      data-index="plugin_id"
                      :width="180"
                    />
                    <a-table-column
                      :title="t('admin.applications.lifecycle.version')"
                      data-index="current_version"
                      :width="120"
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
                      data-index="desired_state"
                      :width="150"
                    />
                    <a-table-column
                      :title="t('admin.applications.lifecycle.updatedAt')"
                      data-index="updated_at"
                      :width="190"
                    />
                  </template>
                  <template #empty>
                    <a-empty :description="t('admin.applications.lifecycle.noInstallations')" />
                  </template>
                </a-table>
              </a-grid-item>
              <a-grid-item>
                <a-table
                  :data="pluginLifecycle.runs"
                  :pagination="{ pageSize: 10 }"
                  :bordered="{ cell: true }"
                  :scroll="{ x: 760 }"
                  row-key="operation_id"
                  size="small"
                >
                  <template #columns>
                    <a-table-column
                      :title="t('admin.applications.lifecycle.plugin')"
                      data-index="plugin_id"
                      :width="170"
                    />
                    <a-table-column :title="t('admin.applications.lifecycle.action')" :width="130">
                      <template #cell="{ record }">
                        {{ t(`admin.applications.generations.actions.${record.action}`) }}
                      </template>
                    </a-table-column>
                    <a-table-column :title="t('admin.applications.lifecycle.runState')" :width="140">
                      <template #cell="{ record }">
                        <a-tag :color="lifecycleStatusColor(record.state)">
                          {{ lifecycleLabel(record.state) }}
                        </a-tag>
                      </template>
                    </a-table-column>
                    <a-table-column :title="t('admin.applications.lifecycle.details')" :width="100">
                      <template #cell="{ record }">
                        <a-button size="small" @click="selectedLifecycleRun = record">
                          {{ t('admin.applications.lifecycle.view') }}
                        </a-button>
                      </template>
                    </a-table-column>
                  </template>
                  <template #empty>
                    <a-empty :description="t('admin.applications.lifecycle.noRuns')" />
                  </template>
                </a-table>
              </a-grid-item>
            </a-grid>
          </a-card>

          <a-card
            v-if="pluginCapabilities.diagnostics"
            :title="t('admin.applications.generations.title')"
            :bordered="true"
          >
            <a-alert
              v-if="!pluginRuntimeGenerations.available"
              type="warning"
              :title="t('admin.applications.generations.unavailable')"
              show-icon
            />
            <a-collapse v-else-if="pluginRuntimeGenerations.generations.length" accordion>
              <a-collapse-item
                v-for="generation in pluginRuntimeGenerations.generations"
                :key="generation.number"
                :name="String(generation.number)"
                :header="t('admin.applications.generations.generation', { number: generation.number })"
              >
                <a-space direction="vertical" :size="12" fill>
                  <a-space wrap>
                    <a-tag :color="generationStatusColor(generation.state)">
                      {{ t(`admin.applications.generations.states.${generation.state}`) }}
                    </a-tag>
                    <a-tag bordered>
                      {{ t(`admin.applications.generations.actions.${generation.action}`) }}
                    </a-tag>
                  </a-space>
                  <a-descriptions :column="{ xs: 1, sm: 2 }" bordered size="small">
                    <a-descriptions-item :label="t('admin.applications.generations.target')">
                      {{ generation.target_plugin_id || '—' }}
                    </a-descriptions-item>
                    <a-descriptions-item :label="t('admin.applications.generations.requiredAcks')">
                      {{
                        t('admin.applications.generations.requiredAcksValue', {
                          ratio: generation.minimum_ack_ratio,
                          count: generation.expected_process_count,
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
                    v-if="generation.error_message"
                    type="error"
                    :title="t('admin.applications.generations.error')"
                    :description="generation.error_message"
                    show-icon
                  />
                  <a-table
                    :data="generation.acknowledgements"
                    :pagination="false"
                    :bordered="{ cell: true }"
                    :scroll="{ x: 820 }"
                    row-key="process_ref"
                    size="small"
                  >
                    <template #columns>
                      <a-table-column
                        :title="t('admin.applications.generations.process')"
                        data-index="process_ref"
                        :width="220"
                      />
                      <a-table-column :title="t('admin.applications.generations.status')" :width="140">
                        <template #cell="{ record }">
                          <a-tag :color="generationStatusColor(record.status)">
                            {{ t(`admin.applications.generations.ackStates.${record.status}`) }}
                          </a-tag>
                        </template>
                      </a-table-column>
                      <a-table-column :title="t('admin.applications.generations.loadedPlugins')">
                        <template #cell="{ record }">
                          <a-space wrap size="mini">
                            <a-tag
                              v-for="(version, pluginId) in record.plugin_versions"
                              :key="pluginId"
                              bordered
                            >
                              {{ pluginId }} · {{ version }}
                            </a-tag>
                          </a-space>
                        </template>
                      </a-table-column>
                      <a-table-column
                        :title="t('admin.applications.generations.lastSeen')"
                        data-index="last_seen_at"
                        :width="190"
                      />
                    </template>
                    <template #empty>
                      <a-empty :description="t('admin.applications.generations.noAcks')" />
                    </template>
                  </a-table>
                </a-space>
              </a-collapse-item>
            </a-collapse>
            <a-empty v-else :description="t('admin.applications.generations.empty')" />
          </a-card>
        </a-space>
      </a-tab-pane>

      <a-tab-pane key="extensions" :title="t('admin.applications.extensionsTitle')">
        <a-space direction="vertical" :size="16" fill>
          <a-typography-paragraph type="secondary">
            {{ t('admin.applications.extensionsHint') }}
          </a-typography-paragraph>
          <a-grid :cols="{ xs: 1, lg: 2 }" :col-gap="16" :row-gap="16">
            <a-grid-item v-for="item in extensions" :key="item.id">
              <a-card :bordered="true" hoverable>
                <template #title>
                  <a-space wrap>
                    <a-typography-text bold>{{ item.label }}</a-typography-text>
                    <a-tag>{{ t('admin.applications.tierExtension') }}</a-tag>
                    <a-tag v-if="item.kind" bordered>{{ item.kind }}</a-tag>
                  </a-space>
                </template>
                <a-space direction="vertical" :size="16" fill>
                  <a-typography-paragraph>{{ item.description }}</a-typography-paragraph>
                  <a-descriptions
                    v-if="item.host || item.capabilities?.length || item.limitations?.length"
                    :column="1"
                    bordered
                    size="small"
                  >
                    <a-descriptions-item
                      v-if="item.host"
                      :label="t('admin.applications.hostLabel')"
                    >
                      {{ item.host }}
                    </a-descriptions-item>
                    <a-descriptions-item
                      v-if="item.capabilities?.length"
                      :label="t('admin.applications.pluginCapabilities')"
                    >
                      <a-space wrap size="mini">
                        <a-tag
                          v-for="capability in item.capabilities"
                          :key="capability"
                          bordered
                        >
                          {{ capability }}
                        </a-tag>
                      </a-space>
                    </a-descriptions-item>
                    <a-descriptions-item
                      v-if="item.limitations?.length"
                      :label="t('admin.applications.limitationsLabel')"
                    >
                      <a-space direction="vertical" size="mini" fill>
                        <a-typography-text
                          v-for="(line, index) in item.limitations"
                          :key="index"
                          type="secondary"
                        >
                          {{ line }}
                        </a-typography-text>
                      </a-space>
                    </a-descriptions-item>
                  </a-descriptions>
                </a-space>
              </a-card>
            </a-grid-item>
          </a-grid>
        </a-space>
      </a-tab-pane>
      </a-tabs>
    </a-card>

    <Drawer
      :visible="selectedCatalogRelease !== null"
      :title="t('admin.applications.catalog.detailTitle')"
      :width="720"
      unmount-on-close
      @cancel="selectedCatalogRelease = null"
    >
      <a-space v-if="selectedCatalogRelease" direction="vertical" :size="16" fill>
        <a-descriptions :column="{ xs: 1, sm: 2 }" bordered size="small">
          <a-descriptions-item :label="t('admin.applications.catalog.plugin')">
            {{ selectedCatalogRelease.plugin_id }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.catalog.releaseIdentity')">
            {{ selectedCatalogRelease.version }} · API {{ selectedCatalogRelease.api_version }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.catalog.manifestDigest')">
            <a-typography-text code copyable>
              {{ selectedCatalogRelease.manifest_sha256 }}
            </a-typography-text>
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.catalog.packageDigest')">
            <a-space direction="vertical" size="mini" fill>
              <a-typography-text code copyable>
                {{ selectedCatalogRelease.package_sha256 }}
              </a-typography-text>
              <a-tag bordered>
                {{
                  t(
                    `admin.applications.catalog.digestSources.${selectedCatalogRelease.package_digest_source}`,
                  )
                }}
              </a-tag>
            </a-space>
          </a-descriptions-item>
        </a-descriptions>

        <a-alert
          v-for="diagnostic in selectedCatalogRelease.diagnostics"
          :key="`${diagnostic.code}-${diagnostic.severity}`"
          :type="diagnostic.severity === 'error' ? 'error' : 'warning'"
          :title="t(`admin.applications.catalog.findings.${diagnostic.code}`)"
          show-icon
        />

        <a-table
          :data="selectedCatalogRelease.contributions"
          :pagination="false"
          :bordered="{ cell: true }"
          :scroll="{ x: 720 }"
          row-key="id"
          size="small"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.catalog.contributionId')"
              data-index="id"
              :width="220"
            />
            <a-table-column
              :title="t('admin.applications.catalog.contributionType')"
              data-index="type"
              :width="150"
            />
            <a-table-column
              :title="t('admin.applications.catalog.schemaDigest')"
              data-index="schema_sha256"
              :width="300"
            />
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.catalog.noContributions')" />
          </template>
        </a-table>

        <a-table
          :data="selectedCatalogRelease.file_issues"
          :pagination="{ pageSize: 12 }"
          :bordered="{ cell: true }"
          :scroll="{ x: 820 }"
          row-key="path"
          size="small"
        >
          <template #columns>
            <a-table-column
              :title="t('admin.applications.catalog.filePath')"
              data-index="path"
              :width="300"
            />
            <a-table-column :title="t('admin.applications.catalog.health')" :width="140">
              <template #cell="{ record }">
                <a-tag :color="marketplaceStatusColor(record.health)">
                  {{ marketplaceStatusLabel(record.health) }}
                </a-tag>
              </template>
            </a-table-column>
            <a-table-column :title="t('admin.applications.catalog.fileSize')" :width="180">
              <template #cell="{ record }">
                {{ record.observed_size ?? '—' }} / {{ record.expected_size }}
              </template>
            </a-table-column>
          </template>
          <template #empty>
            <a-empty :description="t('admin.applications.catalog.noFileIssues')" />
          </template>
        </a-table>
      </a-space>
    </Drawer>

    <Drawer
      :visible="selectedLifecycleRun !== null"
      :title="t('admin.applications.lifecycle.detailTitle')"
      :width="680"
      unmount-on-close
      @cancel="selectedLifecycleRun = null"
    >
      <a-space v-if="selectedLifecycleRun" direction="vertical" :size="16" fill>
        <a-descriptions :column="{ xs: 1, sm: 2 }" bordered size="small">
          <a-descriptions-item :label="t('admin.applications.lifecycle.plugin')">
            {{ selectedLifecycleRun.plugin_id || '—' }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.lifecycle.operation')">
            {{ selectedLifecycleRun.operation_id }}
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
            {{ selectedLifecycleRun.from_version || '—' }} →
            {{ selectedLifecycleRun.to_version || '—' }}
          </a-descriptions-item>
        </a-descriptions>
        <a-alert
          v-if="selectedLifecycleRun.error_message"
          type="error"
          :title="t('admin.applications.lifecycle.failed')"
          :description="selectedLifecycleRun.error_message"
          show-icon
        />
        <Timeline v-if="selectedLifecycleRun.steps.length">
          <TimelineItem
            v-for="step in selectedLifecycleRun.steps"
            :key="step.sequence"
            :dot-color="lifecycleStatusColor(step.state)"
          >
            <a-space direction="vertical" size="mini" fill>
              <a-typography-text bold>
                {{ t(`admin.applications.lifecycle.steps.${step.step_key}`) }}
              </a-typography-text>
              <a-typography-text type="secondary">
                {{ lifecycleLabel(step.state) }}
              </a-typography-text>
              <a-typography-text v-if="step.error_message" type="danger">
                {{ step.error_message }}
              </a-typography-text>
            </a-space>
          </TimelineItem>
        </Timeline>
        <a-empty v-else :description="t('admin.applications.lifecycle.noSteps')" />
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
      <a-space direction="vertical" :size="16" fill>
        <a-alert
          type="error"
          show-icon
          :closable="false"
          :title="t('admin.applications.marketplace.uninstallRiskTitle')"
        >
          {{
            t('admin.applications.marketplace.uninstallConfirmMessage', {
              plugin: uninstallTarget?.name || uninstallTarget?.id,
            })
          }}
        </a-alert>

        <a-descriptions
          v-if="uninstallTarget"
          :column="{ xs: 1, sm: 2 }"
          layout="vertical"
          bordered
          size="small"
        >
          <a-descriptions-item :label="t('admin.applications.marketplace.version')">
            {{ uninstallTarget.version }}
          </a-descriptions-item>
          <a-descriptions-item :label="t('admin.applications.marketplace.checksum')">
            <a-typography-text code copyable>
              {{ uninstallTarget.sha256 }}
            </a-typography-text>
          </a-descriptions-item>
        </a-descriptions>

        <a-alert
          type="warning"
          show-icon
          :title="t(`admin.applications.marketplace.dataModes.${uninstallDataMode}.warningTitle`)"
        >
          {{
            t(`admin.applications.marketplace.dataModes.${uninstallDataMode}.warning`, {
              plugin: uninstallTarget?.name || uninstallTarget?.id,
            })
          }}
        </a-alert>

        <a-form
          :model="{ confirmation: uninstallConfirmation, data_mode: uninstallDataMode }"
          layout="vertical"
        >
          <a-form-item
            field="data_mode"
            :label="t('admin.applications.marketplace.uninstallDataModeLabel')"
          >
            <a-radio-group v-model="uninstallDataMode" direction="vertical">
              <a-radio
                v-if="pluginCapabilities.uninstall_preserve"
                value="preserve_data"
              >
                {{ t('admin.applications.marketplace.dataModes.preserve_data.label') }}
              </a-radio>
              <a-radio
                v-if="pluginCapabilities.uninstall_purge"
                value="purge_data"
              >
                {{ t('admin.applications.marketplace.dataModes.purge_data.label') }}
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

        <a-row justify="end">
          <a-space wrap>
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
          </a-space>
        </a-row>
      </a-space>
    </a-modal>
  </a-space>
</template>
