<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import { computed, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import type { FileItem } from '@arco-design/web-vue'
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

const props = defineProps<{
  title: string
  platform: CatalogItem[]
  applications: CatalogItem[]
  extensions: CatalogItem[]
  plugins: PluginItem[]
  pluginDiagnostics: PluginDiagnostic[]
  pluginMarketplace: MarketplaceSnapshot
  pluginActions: {
    install: string
    enable: string
    disable: string
    uninstall: string
  }
  canManagePlugins: boolean
  freelyExtensible: boolean
  featureFlagsUrl: string
}>()

const pluginFiles = ref<FileItem[]>([])
const uninstallTarget = ref<MarketplacePlugin | null>(null)
const uninstallConfirmation = ref('')
const uninstallSubmitting = ref(false)
const uninstallModalVisible = computed({
  get: () => uninstallTarget.value !== null,
  set: (visible: boolean) => {
    if (!visible) closeUninstall()
  },
})
const canUninstall = computed(
  () => uninstallTarget.value !== null &&
    hasVerifiedUninstallIdentity(uninstallTarget.value) &&
    uninstallConfirmation.value.trim() === uninstallTarget.value.id,
)
const installForm = useForm<{
  plugin_package: File | null
  expected_sha256: string
  expected_id: string
  allow_downgrade: boolean
}>({
  plugin_package: null,
  expected_sha256: '',
  expected_id: '',
  allow_downgrade: false,
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
    'not_loaded',
    'succeeded',
    'failed',
    'started',
  ]
  return known.includes(status)
    ? t(`admin.applications.marketplace.statusLabels.${status}`)
    : status
}

function marketplaceStatusColor(status: string) {
  if (status === 'active' || status === 'installed' || status === 'succeeded') return 'green'
  if (status === 'disabled' || status === 'not_loaded' || status === 'started') return 'orange'
  if (status === 'failed') return 'red'
  return 'gray'
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
      installForm.reset()
      pluginFiles.value = []
    },
  })
}

function changePluginState(action: 'enable' | 'disable', pluginId: string) {
  router.post(
    props.pluginActions[action],
    { plugin_id: pluginId },
    { preserveScroll: true },
  )
}

function openUninstall(plugin: MarketplacePlugin) {
  if (!hasVerifiedUninstallIdentity(plugin)) return

  uninstallTarget.value = plugin
  uninstallConfirmation.value = ''
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
    },
    preserveScroll: true,
    onStart: () => {
      uninstallSubmitting.value = true
    },
    onSuccess: () => {
      uninstallTarget.value = null
      uninstallConfirmation.value = ''
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
        v-if="canManagePlugins"
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
            {{ t('admin.applications.marketplace.install') }}
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
            </a-descriptions>
            <a-space v-if="canManagePlugins" wrap class="mt-3">
              <a-button
                v-if="plugin.filesystem_status === 'disabled'"
                size="small"
                @click="changePluginState('enable', plugin.id)"
              >
                {{ t('admin.applications.marketplace.enable') }}
              </a-button>
              <a-button
                v-if="plugin.filesystem_status === 'installed'"
                size="small"
                @click="changePluginState('disable', plugin.id)"
              >
                {{ t('admin.applications.marketplace.disable') }}
              </a-button>
              <a-button
                v-if="['installed', 'disabled'].includes(plugin.filesystem_status) &&
                  hasVerifiedUninstallIdentity(plugin)"
                size="small"
                status="danger"
                @click="openUninstall(plugin)"
              >
                {{ t('admin.applications.marketplace.uninstall') }}
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

  <a-modal
    v-model:visible="uninstallModalVisible"
    :title="t('admin.applications.marketplace.uninstallConfirmTitle')"
    :footer="false"
    :mask-closable="!uninstallSubmitting"
    :esc-to-close="!uninstallSubmitting"
    :width="'min(620px, calc(100vw - 32px))'"
  >
    <a-alert
      type="error"
      show-icon
      :closable="false"
      :title="t('admin.applications.marketplace.uninstallRiskTitle')"
      class="mb-5"
    >
      {{
        t('admin.applications.marketplace.uninstallConfirmMessage', {
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

    <a-form :model="{ confirmation: uninstallConfirmation }" layout="vertical">
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
        {{ t('admin.applications.marketplace.uninstall') }}
      </a-button>
    </div>
  </a-modal>
</template>
