<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { computed, ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { IconInfoCircle } from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'
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

const { t } = useI18n()

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
  settings: SettingItem[]
}>()

const form = useForm({
  settings: Object.fromEntries(props.settings.map((setting) => [setting.key, setting.value])),
})
const baselineSettings = ref<Record<string, string>>({ ...form.settings })

const query = ref('')
const activeGroup = ref<SystemSettingGroup>('general')

const displaySettings = computed<DisplaySetting[]>(() => props.settings.map((setting) => ({
  ...setting,
  group: systemSettingGroup(setting.key),
  inputType: setting.sensitive ? 'password' : systemSettingInputType(setting.key),
  readOnly: systemSettingReadOnly(setting.key),
})))

const groups = computed(() => {
  const normalizedQuery = query.value.trim().toLocaleLowerCase()

  return SYSTEM_SETTING_GROUP_ORDER.map((key) => {
    const settings = displaySettings.value.filter((setting) => {
      if (setting.group !== key) return false
      if (!normalizedQuery) return true

      return [setting.label, setting.hint, setting.key]
        .filter(Boolean)
        .some((value) => String(value).toLocaleLowerCase().includes(normalizedQuery))
    })

    return { key, settings }
  }).filter((group) => group.settings.length > 0)
})

const changedSettings = computed(() => Object.fromEntries(
  Object.entries(form.settings).filter(([key, value]) => value !== baselineSettings.value[key]),
))
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

function fieldError(key: string) {
  return form.errors[key] || form.errors[`settings.${key}`]
}

function numberValue(key: string) {
  const value = Number(form.settings[key])
  return Number.isFinite(value) ? value : undefined
}

function updateNumber(key: string, value: number | undefined) {
  form.settings[key] = value == null ? '' : String(value)
}

function updateBoolean(key: string, enabled: boolean) {
  form.settings[key] = systemSettingBooleanStorage(key, enabled)
}

function submit() {
  form.transform(() => ({ settings: changedSettings.value }))
  form.patch(adminRoutes.settings, {
    preserveScroll: true,
    onSuccess: () => {
      for (const setting of props.settings) {
        if (setting.sensitive) form.settings[setting.key] = ''
      }
      baselineSettings.value = { ...form.settings }
      form.defaults()
    },
  })
}

function resetChanges() {
  form.settings = { ...baselineSettings.value }
  form.clearErrors()
}
</script>

<template>
  <a-space direction="vertical" :size="20" fill>
    <a-page-header
      :title="t('admin.systemSettings.title')"
      :subtitle="t('admin.systemSettings.subtitle')"
      :show-back="false"
    >
      <template #extra>
        <a-space wrap size="small">
          <a-button :href="adminRoutes.jobs" data-admin-hard-navigation>
            {{ t('admin.common.backgroundJobs') }}
          </a-button>
          <a-button href="/health/ready" data-admin-hard-navigation>
            {{ t('admin.common.healthCheck') }}
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-alert
      type="info"
      show-icon
      :title="t('admin.systemSettings.localizedNoticeTitle')"
      :content="t('admin.systemSettings.localizedNotice')"
    />

    <a-card :bordered="true">
      <a-form
        v-if="settings.length"
        :model="form.settings"
        layout="vertical"
        @submit="submit"
      >
        <a-space direction="vertical" :size="16" fill>
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
                      :field="setting.key"
                      :label="setting.label"
                      :validate-status="fieldError(setting.key) ? 'error' : undefined"
                      :help="fieldError(setting.key) || setting.hint || undefined"
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
                          :model-value="systemSettingBooleanValue(form.settings[setting.key])"
                          :disabled="setting.readOnly"
                          @change="(value: boolean) => updateBoolean(setting.key, value)"
                        />
                        <a-typography-text type="secondary">
                          {{
                            systemSettingBooleanValue(form.settings[setting.key])
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
                        v-model="form.settings[setting.key]"
                        allow-clear
                        :placeholder="
                          setting.configured
                            ? t('admin.systemSettings.secretConfigured')
                            : t('admin.systemSettings.secretNotConfigured')
                        "
                      />

                      <a-textarea
                        v-else-if="setting.inputType === 'textarea'"
                        v-model="form.settings[setting.key]"
                        :auto-size="{ minRows: 2, maxRows: 6 }"
                        :readonly="setting.readOnly"
                        allow-clear
                      />

                      <a-input
                        v-else
                        v-model="form.settings[setting.key]"
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
              :loading="form.processing"
              :disabled="changedCount === 0"
            >
              {{ t('admin.systemSettings.saveChanges', { count: changedCount }) }}
            </a-button>
            <a-button
              :disabled="changedCount === 0 || form.processing"
              @click="resetChanges"
            >
              {{ t('admin.systemSettings.reset') }}
            </a-button>
            <a-tag v-if="form.recentlySuccessful" color="green">
              {{ t('admin.common.saved') }}
            </a-tag>
          </a-space>
        </a-space>
      </a-form>

      <a-empty v-else :description="t('admin.systemSettings.empty')" />
    </a-card>
  </a-space>
</template>
