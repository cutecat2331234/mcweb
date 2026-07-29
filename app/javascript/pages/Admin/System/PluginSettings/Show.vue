<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { router } from '@inertiajs/vue3'
import { Modal } from '@mcweb/ui'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

type Scalar = string | number | boolean | null

interface CatalogEntry {
  plugin_id: string
  plugin_name: string
  plugin_version: string
  status: string
  schema_version: string
}

interface SettingField {
  key: string
  type: 'string' | 'integer' | 'number' | 'boolean'
  input: 'text' | 'password' | 'textarea' | 'url' | 'email' | 'select' | 'number' | 'switch'
  required: boolean
  sensitive: boolean
  configured: boolean
  value?: Scalar
  label: string
  description?: string | null
  placeholder?: string | null
  enum?: Array<{ value: Exclude<Scalar, null>; label: string }> | null
  minimum?: number | null
  maximum?: number | null
  min_length?: number | null
  max_length?: number | null
  error?: string | null
}

interface SettingGroup {
  key: string
  title: string
  description?: string | null
  fields: SettingField[]
}

interface HistoryEntry {
  id: number
  schema_version: string
  schema_digest: string
  revision: number
  change_kind: string
  actor?: { public_id?: string | null; username: string } | null
  migration_source?: { id: number; schema_version: string; revision: number } | null
  rollback_source?: { id: number; schema_version: string; revision: number } | null
  current_schema: boolean
  created_at?: string | null
}

interface SelectedSettings {
  plugin_id: string
  plugin_name: string
  plugin_version: string
  status: string
  schema_version: string
  schema_digest: string
  revision: number
  complete: boolean
  migration_available: boolean
  persisted_at?: string | null
  page_error?: string | null
  groups: SettingGroup[]
  history: HistoryEntry[]
}

const props = defineProps<{
  title: string
  catalog: CatalogEntry[]
  selected?: SelectedSettings | null
  actions: {
    show: string
    update: string
    migrate: string
    rollback: string
  }
}>()

const { t, locale } = useI18n()
const processing = ref(false)
const formValues = ref<Record<string, Scalar | undefined>>({})
const unsetValues = ref<Record<string, boolean>>({})

const fields = computed(() => props.selected?.groups.flatMap((group) => group.fields) ?? [])
const pluginOptions = computed(() => props.catalog.map((plugin) => ({
  value: plugin.plugin_id,
  label: `${plugin.plugin_name} · ${plugin.plugin_id}`,
})))

watch(
  () => `${props.selected?.plugin_id ?? ''}:${props.selected?.revision ?? 0}:${props.selected?.page_error ?? ''}`,
  () => {
    const nextValues: Record<string, Scalar | undefined> = {}
    const nextUnset: Record<string, boolean> = {}
    for (const field of fields.value) {
      nextValues[field.key] = field.sensitive ? '' : field.value
      nextUnset[field.key] = false
    }
    formValues.value = nextValues
    unsetValues.value = nextUnset
  },
  { immediate: true },
)

function selectPlugin(value: string | number | boolean | Record<string, unknown> | undefined) {
  if (typeof value !== 'string') return
  router.get(props.actions.show, { plugin_id: value }, {
    preserveScroll: true,
    preserveState: true,
    replace: true,
  })
}

function submit() {
  if (!props.selected || processing.value) return

  const values: Record<string, Scalar> = {}
  const unsetKeys: string[] = []
  for (const field of fields.value) {
    if (unsetValues.value[field.key]) {
      unsetKeys.push(field.key)
      continue
    }

    const value = formValues.value[field.key]
    if (field.sensitive) {
      if (typeof value === 'string' && value.length > 0) values[field.key] = value
    } else if (value !== undefined && value !== null) {
      values[field.key] = value
    }
  }

  processing.value = true
  router.patch(props.actions.update, {
    plugin_id: props.selected.plugin_id,
    expected_revision: props.selected.revision,
    values,
    unset_keys: unsetKeys,
  }, {
    preserveScroll: true,
    onFinish: () => { processing.value = false },
  })
}

function migrateSettings() {
  if (!props.selected || processing.value) return
  processing.value = true
  router.post(props.actions.migrate, {
    plugin_id: props.selected.plugin_id,
    expected_revision: props.selected.revision,
  }, {
    preserveScroll: true,
    onFinish: () => { processing.value = false },
  })
}

function rollbackSettings(entry: HistoryEntry) {
  if (!props.selected || processing.value) return

  Modal.warning({
    title: t('admin.pluginSettings.rollbackTitle'),
    content: t('admin.pluginSettings.rollbackConfirm', { revision: entry.revision }),
    okText: t('admin.pluginSettings.rollback'),
    cancelText: t('admin.ui.cancel'),
    hideCancel: false,
    onOk: () => {
      if (!props.selected) return
      processing.value = true
      router.post(props.actions.rollback, {
        plugin_id: props.selected.plugin_id,
        revision: entry.revision,
        expected_revision: props.selected.revision,
      }, {
        preserveScroll: true,
        onFinish: () => { processing.value = false },
      })
    },
  })
}

function statusColor(status: string) {
  if (status === 'active') return 'green'
  if (status === 'degraded') return 'orange'
  if (status === 'disabled') return 'red'
  return 'gray'
}

function statusLabel(status: string) {
  const known = ['registered', 'active', 'degraded', 'disabled']
  return known.includes(status) ? t(`admin.applications.pluginStatus.${status}`) : status
}

function changeKindLabel(kind: string) {
  const known = ['update', 'migration', 'rollback']
  return known.includes(kind) ? t(`admin.pluginSettings.changeKinds.${kind}`) : kind
}

function formatTime(value?: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat(locale.value, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function sourceLabel(entry: HistoryEntry) {
  const source = entry.migration_source ?? entry.rollback_source
  if (!source) return '—'
  return t('admin.pluginSettings.sourceRevision', {
    schema: source.schema_version,
    revision: source.revision,
  })
}
</script>

<template>
  <a-page-header
    :title="title"
    :subtitle="t('admin.pluginSettings.subtitle')"
    class="mb-5 !px-0"
  />

  <a-alert
    type="info"
    show-icon
    :title="t('admin.pluginSettings.securityTitle')"
    class="mb-6"
  >
    {{ t('admin.pluginSettings.securityNotice') }}
  </a-alert>

  <a-empty
    v-if="catalog.length === 0"
    :description="t('admin.pluginSettings.empty')"
  />

  <template v-else>
    <a-card :bordered="false" class="mb-6 bg-[var(--color-fill-1)]">
      <div class="grid items-end gap-4 md:grid-cols-[minmax(0,1fr)_auto]">
        <a-form-item
          :label="t('admin.pluginSettings.pluginLabel')"
          class="!mb-0"
        >
          <a-select
            :model-value="selected?.plugin_id"
            :options="pluginOptions"
            allow-search
            class="w-full"
            @change="selectPlugin"
          />
        </a-form-item>

        <a-space v-if="selected" wrap :size="[6, 6]">
          <a-tag :color="statusColor(selected.status)">
            {{ statusLabel(selected.status) }}
          </a-tag>
          <a-tag>v{{ selected.plugin_version }}</a-tag>
          <a-tag>{{ t('admin.pluginSettings.schemaVersion', { version: selected.schema_version }) }}</a-tag>
          <a-tag>
            {{ t('admin.pluginSettings.revision', { revision: selected.revision }) }}
          </a-tag>
        </a-space>
      </div>
      <p v-if="selected" class="mt-3 break-all font-mono text-xs text-[var(--color-text-3)]">
        {{ selected.plugin_id }} · {{ selected.schema_digest }}
      </p>
    </a-card>

    <template v-if="selected">
      <a-alert
        v-if="selected.page_error"
        type="error"
        show-icon
        :title="t('admin.pluginSettings.errorTitle')"
        class="mb-5"
      >
        {{ selected.page_error }}
      </a-alert>

      <a-alert
        v-if="selected.migration_available"
        type="warning"
        show-icon
        :title="t('admin.pluginSettings.migrationTitle')"
        class="mb-5"
      >
        <div class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
          <span>{{ t('admin.pluginSettings.migrationNotice') }}</span>
          <a-button
            type="primary"
            :loading="processing"
            @click="migrateSettings"
          >
            {{ t('admin.pluginSettings.migrate') }}
          </a-button>
        </div>
      </a-alert>

      <a-form
        v-if="selected.groups.length"
        :model="formValues"
        layout="vertical"
        @submit="submit"
      >
        <div class="space-y-6">
          <section
            v-for="group in selected.groups"
            :key="group.key"
            class="rounded-md bg-[var(--color-fill-1)] p-4 sm:p-5"
          >
            <div class="mb-5">
              <h2 class="text-base font-semibold text-[var(--color-text-1)]">
                {{ group.title }}
              </h2>
              <p
                v-if="group.description"
                class="mt-1 max-w-3xl text-sm leading-6 text-[var(--color-text-3)]"
              >
                {{ group.description }}
              </p>
            </div>

            <div class="grid gap-x-6 gap-y-1 lg:grid-cols-2">
              <a-form-item
                v-for="field in group.fields"
                :key="field.key"
                :field="field.key"
                :label="field.label"
                :required="field.required"
                :validate-status="field.error ? 'error' : undefined"
                :help="field.error || undefined"
                :class="{ 'lg:col-span-2': field.input === 'textarea' }"
              >
                <a-textarea
                  v-if="field.input === 'textarea'"
                  v-model="formValues[field.key]"
                  :placeholder="field.placeholder || undefined"
                  :max-length="field.max_length || undefined"
                  :disabled="unsetValues[field.key]"
                  auto-size
                  allow-clear
                />
                <a-input-password
                  v-else-if="field.input === 'password'"
                  v-model="formValues[field.key]"
                  :placeholder="field.placeholder || t('admin.pluginSettings.secretPlaceholder')"
                  :max-length="field.max_length || undefined"
                  :disabled="unsetValues[field.key]"
                  allow-clear
                  autocomplete="new-password"
                />
                <a-select
                  v-else-if="field.input === 'select'"
                  v-model="formValues[field.key]"
                  :options="field.enum || []"
                  :placeholder="field.placeholder || undefined"
                  :disabled="unsetValues[field.key]"
                  :allow-clear="!field.required"
                />
                <a-input-number
                  v-else-if="field.input === 'number'"
                  v-model="formValues[field.key]"
                  :min="field.minimum ?? undefined"
                  :max="field.maximum ?? undefined"
                  :precision="field.type === 'integer' ? 0 : undefined"
                  :placeholder="field.placeholder || undefined"
                  :disabled="unsetValues[field.key]"
                  class="w-full"
                  :allow-clear="!field.required"
                />
                <a-switch
                  v-else-if="field.input === 'switch'"
                  v-model="formValues[field.key]"
                  :disabled="unsetValues[field.key]"
                  :checked-text="t('admin.ui.enabled')"
                  :unchecked-text="t('admin.ui.disabled')"
                />
                <a-input
                  v-else
                  v-model="formValues[field.key]"
                  :type="field.input === 'email' ? 'email' : field.input === 'url' ? 'url' : 'text'"
                  :placeholder="field.placeholder || undefined"
                  :max-length="field.max_length || undefined"
                  :disabled="unsetValues[field.key]"
                  allow-clear
                />

                <template #extra>
                  <div class="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1">
                    <span v-if="field.description" class="leading-5">
                      {{ field.description }}
                    </span>
                    <a-tag
                      v-if="field.sensitive"
                      :color="field.configured ? 'green' : 'gray'"
                      size="small"
                    >
                      {{
                        field.configured
                          ? t('admin.pluginSettings.secretConfigured')
                          : t('admin.pluginSettings.secretNotConfigured')
                      }}
                    </a-tag>
                    <a-checkbox
                      v-if="!field.required && field.configured"
                      v-model="unsetValues[field.key]"
                    >
                      {{
                        field.sensitive
                          ? t('admin.pluginSettings.clearSecret')
                          : t('admin.pluginSettings.unsetValue')
                      }}
                    </a-checkbox>
                  </div>
                </template>
              </a-form-item>
            </div>
          </section>
        </div>

        <div class="mt-6 flex flex-wrap items-center gap-3">
          <a-button
            type="primary"
            html-type="submit"
            :loading="processing"
            :disabled="selected.migration_available"
          >
            {{ t('admin.pluginSettings.save') }}
          </a-button>
          <span class="text-sm text-[var(--color-text-3)]">
            {{
              selected.complete
                ? t('admin.pluginSettings.complete')
                : t('admin.pluginSettings.incomplete')
            }}
          </span>
        </div>
      </a-form>

      <a-card
        :bordered="false"
        class="mt-8"
        :title="t('admin.pluginSettings.historyTitle')"
      >
        <p class="mb-4 max-w-3xl text-sm leading-6 text-[var(--color-text-3)]">
          {{ t('admin.pluginSettings.historyNotice') }}
        </p>
        <div class="overflow-x-auto">
          <a-table
            :data="selected.history"
            :pagination="false"
            :bordered="{ wrapper: true, cell: false }"
            row-key="id"
            size="small"
          >
            <template #columns>
              <a-table-column
                :title="t('admin.pluginSettings.historyRevision')"
                :width="150"
              >
                <template #cell="{ record }">
                  <div class="space-y-1">
                    <p class="font-medium">
                      v{{ record.schema_version }} / r{{ record.revision }}
                    </p>
                    <a-tag size="small">
                      {{ changeKindLabel(record.change_kind) }}
                    </a-tag>
                  </div>
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.pluginSettings.historyActor')"
                :width="170"
              >
                <template #cell="{ record }">
                  {{ record.actor?.username || t('admin.pluginSettings.pluginRuntime') }}
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.pluginSettings.historySource')"
                :width="190"
              >
                <template #cell="{ record }">
                  {{ sourceLabel(record) }}
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.pluginSettings.historyTime')"
                :width="210"
              >
                <template #cell="{ record }">
                  {{ formatTime(record.created_at) }}
                </template>
              </a-table-column>
              <a-table-column
                :title="t('admin.ui.actions')"
                :width="120"
                fixed="right"
              >
                <template #cell="{ record }">
                  <a-button
                    v-if="
                      record.current_schema
                        && record.revision < selected.revision
                    "
                    type="text"
                    size="small"
                    :disabled="processing"
                    @click="rollbackSettings(record)"
                  >
                    {{ t('admin.pluginSettings.rollback') }}
                  </a-button>
                  <span v-else>—</span>
                </template>
              </a-table-column>
            </template>
          </a-table>
        </div>
      </a-card>
    </template>
  </template>
</template>
