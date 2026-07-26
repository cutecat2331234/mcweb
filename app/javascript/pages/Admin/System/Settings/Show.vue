<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import { computed, ref, watch, type Component } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  IconApps,
  IconBook,
  IconCloud,
  IconCommand,
  IconDashboard,
  IconExperiment,
  IconHome,
  IconInfoCircle,
  IconLink,
  IconLock,
  IconSafe,
  IconSettings,
  IconStorage,
  IconThunderbolt,
} from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'
import {
  SYSTEM_SETTING_GROUP_ORDER,
  systemSettingBooleanStorage,
  systemSettingBooleanValue,
  systemSettingGroup,
  systemSettingInputType,
  systemSettingReadOnly,
  type SystemSettingGroup,
  type SystemSettingInputType,
} from '@/lib/systemSettings'

defineOptions({ layout: AdminLayout })

type EntryKind = 'configuration' | 'security' | 'extension' | 'operations'

export interface SettingsEntry {
  id: string
  kind: EntryKind
  url: string
}

export interface SettingsSection {
  id: string
  entries: SettingsEntry[]
}

export interface SettingItem {
  key: string
  value: string
  label: string
  hint?: string | null
  sensitive?: boolean
  configured?: boolean
}

interface DisplaySetting extends SettingItem {
  group: SystemSettingGroup
  inputType: SystemSettingInputType
  readOnly: boolean
}

const props = defineProps<{
  sections: SettingsSection[]
  basicSettings: {
    site_name: string
    site_url: string
  }
  formErrors?: Record<string, string>
  updateUrl: string
  settings: SettingItem[]
}>()

const { t } = useI18n()

const basicForm = useForm({
  basic_settings: {
    site_name: props.basicSettings.site_name,
    site_url: props.basicSettings.site_url,
  },
})

const settingsForm = useForm({
  settings: Object.fromEntries(
    props.settings.map((setting) => [setting.key, setting.value]),
  ) as Record<string, string>,
})
const form = settingsForm
const baselineSettings = ref<Record<string, string>>({ ...settingsForm.settings })

const query = ref('')
const activeGroup = ref<SystemSettingGroup>('general')

const entryIcons: Record<string, Component> = {
  feature_toggles: IconThunderbolt,
  forum: IconBook,
  store: IconStorage,
  minecraft: IconCloud,
  rate_limits: IconSafe,
  api_keys: IconLock,
  webhook_subscriptions: IconExperiment,
  applications: IconApps,
  plugin_settings: IconSettings,
  jobs: IconCommand,
  health_overview: IconDashboard,
}

const kindColors: Record<EntryKind, string> = {
  configuration: 'arcoblue',
  security: 'orange',
  extension: 'purple',
  operations: 'green',
}

const entryCount = computed(() =>
  props.sections.reduce((count, section) => count + section.entries.length, 0),
)

const quickEntries = computed(() => {
  const entries = props.sections.flatMap((section) => section.entries)
  return ['feature_toggles', 'rate_limits']
    .map((id) => entries.find((entry) => entry.id === id))
    .filter((entry): entry is SettingsEntry => Boolean(entry))
})

const displaySettings = computed<DisplaySetting[]>(() =>
  props.settings.map((setting) => ({
    ...setting,
    group: systemSettingGroup(setting.key),
    inputType: setting.sensitive ? 'password' : systemSettingInputType(setting.key),
    readOnly: systemSettingReadOnly(setting.key),
  })),
)

const groups = computed(() => {
  const normalizedQuery = query.value.trim().toLocaleLowerCase()

  return SYSTEM_SETTING_GROUP_ORDER.map((key) => {
    const settings = displaySettings.value.filter((setting) => {
      if (setting.group !== key) return false
      if (!normalizedQuery) return true

      return [setting.label, setting.hint, setting.key]
        .filter(Boolean)
        .some((value) =>
          String(value).toLocaleLowerCase().includes(normalizedQuery),
        )
    })

    return { key, settings }
  }).filter((group) => group.settings.length > 0)
})

const changedSettings = computed(() =>
  Object.fromEntries(
    Object.entries(settingsForm.settings).filter(
      ([key, value]) => value !== baselineSettings.value[key],
    ),
  ),
)
const changedCount = computed(() => Object.keys(changedSettings.value).length)

watch(
  groups,
  (nextGroups) => {
    if (!nextGroups.some((group) => group.key === activeGroup.value)) {
      activeGroup.value = nextGroups[0]?.key || 'general'
    }
  },
  { immediate: true },
)

function entryTitle(id: string) {
  return t(`admin.systemSettings.entries.${id}.title`)
}

function entryDescription(id: string) {
  return t(`admin.systemSettings.entries.${id}.description`)
}

function visitEntry(url: string) {
  if (url === window.location.pathname) return

  router.visit(url)
}

function basicFieldError(field: 'site_name' | 'site_url') {
  const code = props.formErrors?.[field]
  if (code) return t(`admin.systemSettings.errors.${code}`)

  return basicForm.errors[`basic_settings.${field}`]
}

function settingFieldError(key: string) {
  return settingsForm.errors[key] || settingsForm.errors[`settings.${key}`]
}

function numberValue(key: string) {
  const value = Number(settingsForm.settings[key])
  return Number.isFinite(value) ? value : undefined
}

function updateNumber(key: string, value: number | undefined) {
  settingsForm.settings[key] = value == null ? '' : String(value)
}

function updateBoolean(key: string, enabled: boolean) {
  settingsForm.settings[key] = systemSettingBooleanStorage(key, enabled)
}

function submitBasicSettings() {
  basicForm.patch(props.updateUrl, {
    preserveScroll: true,
  })
}

function submitSettings() {
  settingsForm.transform(() => ({ settings: changedSettings.value }))
  settingsForm.patch(props.updateUrl, {
    preserveScroll: true,
    onSuccess: () => {
      for (const setting of props.settings) {
        if (setting.sensitive) form.settings[setting.key] = ''
      }
      baselineSettings.value = { ...settingsForm.settings }
      settingsForm.defaults()
    },
  })
}

function resetChanges() {
  settingsForm.settings = { ...baselineSettings.value }
  settingsForm.clearErrors()
}
</script>

<template>
  <a-space direction="vertical" :size="20" fill>
    <a-page-header
      :title="t('admin.systemSettings.title')"
      :subtitle="t('admin.systemSettings.subtitle')"
      :show-back="false"
      class="!px-0"
    >
      <template #extra>
        <a-space wrap size="small">
          <a-button
            v-for="entry in quickEntries"
            :key="entry.id"
            :type="entry.id === 'feature_toggles' ? 'primary' : 'outline'"
            @click="visitEntry(entry.url)"
          >
            <template #icon>
              <component :is="entryIcons[entry.id]" />
            </template>
            {{ entryTitle(entry.id) }}
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-alert
      type="info"
      :title="t('admin.systemSettings.safetyTitle')"
      :description="t('admin.systemSettings.safetyDescription')"
      show-icon
    />

    <a-card
      :title="t('admin.systemSettings.basicTitle')"
      :bordered="true"
    >
      <template #extra>
        <a-tag color="green">
          {{ t('admin.systemSettings.explicitWhitelist') }}
        </a-tag>
      </template>

      <a-typography-paragraph class="!mt-0" type="secondary">
        {{ t('admin.systemSettings.basicDescription') }}
      </a-typography-paragraph>

      <a-form
        :model="basicForm.basic_settings"
        layout="vertical"
        @submit="submitBasicSettings"
      >
        <a-grid
          :cols="{ xs: 1, md: 2 }"
          :col-gap="16"
          :row-gap="0"
        >
          <a-grid-item>
            <a-form-item
              field="basic_settings.site_name"
              :label="t('admin.systemSettings.siteNameLabel')"
              :help="basicFieldError('site_name') || t('admin.systemSettings.siteNameHint')"
              :validate-status="basicFieldError('site_name') ? 'error' : undefined"
            >
              <a-input
                v-model="basicForm.basic_settings.site_name"
                :max-length="80"
                :input-attrs="{ autocomplete: 'organization' }"
                show-word-limit
              >
                <template #prefix><icon-home /></template>
              </a-input>
            </a-form-item>
          </a-grid-item>

          <a-grid-item>
            <a-form-item
              field="basic_settings.site_url"
              :label="t('admin.systemSettings.siteUrlLabel')"
              :help="basicFieldError('site_url') || t('admin.systemSettings.siteUrlHint')"
              :validate-status="basicFieldError('site_url') ? 'error' : undefined"
            >
              <a-input
                v-model="basicForm.basic_settings.site_url"
                :placeholder="t('admin.systemSettings.siteUrlPlaceholder')"
                :input-attrs="{
                  type: 'url',
                  inputmode: 'url',
                  autocomplete: 'url',
                }"
                allow-clear
              >
                <template #prefix><icon-link /></template>
              </a-input>
            </a-form-item>
          </a-grid-item>
        </a-grid>

        <a-space wrap>
          <a-button
            type="primary"
            html-type="submit"
            :loading="basicForm.processing"
          >
            {{ t('admin.systemSettings.saveBasic') }}
          </a-button>
          <a-tag v-if="basicForm.recentlySuccessful" color="green">
            {{ t('admin.common.saved') }}
          </a-tag>
        </a-space>
      </a-form>
    </a-card>

    <a-grid
      :cols="{ xs: 1, lg: 2 }"
      :col-gap="16"
      :row-gap="16"
    >
      <a-grid-item
        v-for="section in sections"
        :key="section.id"
      >
        <a-card :bordered="true" class="h-full">
          <template #title>
            {{ t(`admin.systemSettings.sections.${section.id}.title`) }}
          </template>
          <template #extra>
            <a-tag color="arcoblue">
              {{ t('admin.systemSettings.entryCount', { count: section.entries.length }) }}
            </a-tag>
          </template>

          <a-typography-paragraph class="!mt-0" type="secondary">
            {{ t(`admin.systemSettings.sections.${section.id}.description`) }}
          </a-typography-paragraph>

          <a-space direction="vertical" fill :size="12">
            <Link
              v-for="entry in section.entries"
              :key="entry.id"
              :href="entry.url"
              class="block no-underline"
            >
              <a-card
                size="small"
                :bordered="true"
                hoverable
              >
                <div class="flex min-w-0 items-center gap-3">
                  <a-avatar :size="40" shape="square">
                    <component :is="entryIcons[entry.id] || IconSettings" />
                  </a-avatar>

                  <div class="min-w-0 flex-1">
                    <a-typography-title :heading="6" class="!mb-1 !mt-0">
                      {{ entryTitle(entry.id) }}
                    </a-typography-title>
                    <a-typography-text type="secondary">
                      {{ entryDescription(entry.id) }}
                    </a-typography-text>
                  </div>

                  <a-tag :color="kindColors[entry.kind]" class="shrink-0">
                    {{ t(`admin.systemSettings.kinds.${entry.kind}`) }}
                  </a-tag>
                </div>
              </a-card>
            </Link>
          </a-space>
        </a-card>
      </a-grid-item>
    </a-grid>

    <a-card :bordered="false">
      <a-space wrap>
        <a-tag color="green">
          {{ t('admin.systemSettings.visibleEntryCount', { count: entryCount }) }}
        </a-tag>
        <a-typography-text type="secondary">
          {{ t('admin.systemSettings.permissionNotice') }}
        </a-typography-text>
      </a-space>
    </a-card>

    <a-card
      :title="t('admin.systemSettings.configuration')"
      :bordered="true"
    >
      <a-form
        v-if="settings.length"
        :model="settingsForm.settings"
        layout="vertical"
        @submit="submitSettings"
      >
        <a-space direction="vertical" :size="16" fill>
          <a-alert
            type="info"
            show-icon
            :title="t('admin.systemSettings.localizedNoticeTitle')"
            :content="t('admin.systemSettings.localizedNotice')"
          />

          <a-input-search
            v-model="query"
            allow-clear
            :placeholder="t('admin.systemSettings.searchPlaceholder')"
          />

          <a-tabs v-model:active-key="activeGroup" type="rounded" lazy-load>
            <a-tab-pane
              v-for="group in groups"
              :key="group.key"
              :title="t(`admin.systemSettings.groups.${group.key}`)"
            >
              <a-grid
                :cols="{ xs: 1, md: 2 }"
                :col-gap="16"
                :row-gap="12"
              >
                <a-grid-item
                  v-for="setting in group.settings"
                  :key="setting.key"
                >
                  <a-card size="small" :bordered="true">
                    <a-form-item
                      :field="`settings.${setting.key}`"
                      :label="setting.label"
                      :validate-status="settingFieldError(setting.key) ? 'error' : undefined"
                      :help="settingFieldError(setting.key) || setting.hint || undefined"
                    >
                      <template #label>
                        <a-space :size="6" wrap>
                          <span>{{ setting.label }}</span>
                          <a-tooltip
                            :content="t('admin.systemSettings.technicalKey', { key: setting.key })"
                          >
                            <IconInfoCircle />
                          </a-tooltip>
                          <a-tag v-if="setting.readOnly" size="small">
                            {{ t('admin.systemSettings.automaticValue') }}
                          </a-tag>
                        </a-space>
                      </template>

                      <a-space
                        v-if="setting.inputType === 'boolean'"
                        :size="8"
                      >
                        <a-switch
                          :model-value="systemSettingBooleanValue(settingsForm.settings[setting.key])"
                          :disabled="setting.readOnly"
                          @change="(value: boolean) => updateBoolean(setting.key, value)"
                        />
                        <a-typography-text type="secondary">
                          {{
                            systemSettingBooleanValue(settingsForm.settings[setting.key])
                              ? t('admin.systemSettings.enabled')
                              : t('admin.systemSettings.disabled')
                          }}
                        </a-typography-text>
                      </a-space>

                      <a-input-number
                        v-else-if="setting.inputType === 'number'"
                        :model-value="numberValue(setting.key)"
                        :readonly="setting.readOnly"
                        class="w-full"
                        @change="(value: number | undefined) => updateNumber(setting.key, value)"
                      />

                      <a-input-password
                        v-else-if="setting.inputType === 'password'"
                        v-model="settingsForm.settings[setting.key]"
                        allow-clear
                        :placeholder="
                          setting.configured
                            ? t('admin.systemSettings.secretConfigured')
                            : t('admin.systemSettings.secretNotConfigured')
                        "
                      />

                      <a-textarea
                        v-else-if="setting.inputType === 'textarea'"
                        v-model="settingsForm.settings[setting.key]"
                        :auto-size="{ minRows: 2, maxRows: 6 }"
                        :readonly="setting.readOnly"
                        allow-clear
                      />

                      <a-input
                        v-else
                        v-model="settingsForm.settings[setting.key]"
                        :readonly="setting.readOnly"
                        allow-clear
                      />
                    </a-form-item>
                  </a-card>
                </a-grid-item>
              </a-grid>
            </a-tab-pane>
          </a-tabs>

          <a-empty
            v-if="groups.length === 0"
            :description="t('admin.systemSettings.noResults')"
          />

          <a-divider />

          <a-space wrap size="medium">
            <a-button
              type="primary"
              html-type="submit"
              :loading="settingsForm.processing"
              :disabled="changedCount === 0"
            >
              {{ t('admin.systemSettings.saveChanges', { count: changedCount }) }}
            </a-button>
            <a-button
              :disabled="changedCount === 0 || settingsForm.processing"
              @click="resetChanges"
            >
              {{ t('admin.systemSettings.reset') }}
            </a-button>
            <a-tag v-if="settingsForm.recentlySuccessful" color="green">
              {{ t('admin.common.saved') }}
            </a-tag>
          </a-space>
        </a-space>
      </a-form>

      <a-empty v-else :description="t('admin.systemSettings.empty')" />
    </a-card>
  </a-space>
</template>
