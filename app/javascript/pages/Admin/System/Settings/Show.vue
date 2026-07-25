<script setup lang="ts">
import { computed, ref } from 'vue'
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface SettingItem {
  key: string
  value: string
  category: string
  control: 'text' | 'boolean' | 'number' | 'textarea' | 'password' | 'readonly'
  wide: boolean
  enabled_value: string
  disabled_value: string
}

const props = defineProps<{
  settings: SettingItem[]
}>()

const CATEGORY_ORDER = [
  'site',
  'features',
  'forum',
  'store',
  'minecraft',
  'frontend',
  'webhook',
] as const

const categoryKeys = computed(() => {
  const available = new Set(props.settings.map((setting) => setting.category))
  const ordered = CATEGORY_ORDER.filter((category) => available.has(category))
  const remaining = [...available].filter(
    (category) => !CATEGORY_ORDER.includes(category as (typeof CATEGORY_ORDER)[number]),
  )

  return [...ordered, ...remaining]
})

const activeCategory = ref(categoryKeys.value[0] ?? 'site')
const searchQuery = ref('')
const normalizedSearch = computed(() => searchQuery.value.trim().toLocaleLowerCase())

const form = useForm<any>({
  settings: Object.fromEntries(
    props.settings
      .filter((setting) => setting.control !== 'readonly')
      .map((setting) => [setting.key, setting.value]),
  ),
})

const visibleSettings = computed(() => {
  if (!normalizedSearch.value) {
    return props.settings.filter((setting) => setting.category === activeCategory.value)
  }

  return props.settings.filter((setting) => {
    const label = fieldLabel(setting.key).toLocaleLowerCase()
    return (
      setting.key.toLocaleLowerCase().includes(normalizedSearch.value) ||
      label.includes(normalizedSearch.value)
    )
  })
})

function categoryCount(category: string) {
  return props.settings.filter((setting) => setting.category === category).length
}

function categoryText(category: string, field: 'title' | 'description') {
  const key = `admin.systemSettings.categories.${category}.${field}`
  const translated = t(key)
  return translated === key ? category : translated
}

function fieldLabel(key: string) {
  const translationKey = `admin.systemSettings.fields.${key}`
  const translated = t(translationKey)
  return translated === translationKey ? key : translated
}

function numberValue(key: string) {
  const value = Number(form.settings[key])
  return Number.isFinite(value) ? value : undefined
}

function updateNumberValue(key: string, value: number | undefined) {
  form.settings[key] = value === undefined ? '' : String(value)
}

function fieldError(key: string) {
  const errors = form.errors as Record<string, string | undefined>
  return errors[key] || errors[`settings.${key}`]
}

function submit() {
  form.patch(adminRoutes.settings)
}
</script>

<template>
  <a-space direction="vertical" :size="24" fill>
    <a-page-header
      :title="t('admin.systemSettings.title')"
      :subtitle="t('admin.systemSettings.subtitle')"
      :show-back="false"
    >
      <template #extra>
        <a-space wrap size="small">
          <a-button
            type="primary"
            :loading="form.processing"
            :disabled="!settings.length"
            @click="submit"
          >
            {{ t('admin.systemSettings.save') }}
          </a-button>
          <a-button :href="adminRoutes.jobs">
            {{ t('admin.common.backgroundJobs') }}
          </a-button>
          <a-button href="/health/ready">
            {{ t('admin.common.healthCheck') }}
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-row justify="center">
      <a-col :xs="24" :lg="23" :xxl="21">
        <a-card :title="t('admin.systemSettings.configuration')" :bordered="true">
          <template #extra>
            <a-tag color="arcoblue" round>
              {{ t('admin.systemSettings.settingCount', { count: settings.length }) }}
            </a-tag>
          </template>

          <a-form
            v-if="settings.length"
            :model="form.settings"
            layout="vertical"
            @submit="submit"
          >
            <a-space direction="vertical" :size="20" fill>
              <a-input-search
                v-model="searchQuery"
                size="large"
                allow-clear
                :placeholder="t('admin.systemSettings.searchPlaceholder')"
              />

              <a-tabs
                v-if="!normalizedSearch"
                v-model:active-key="activeCategory"
                type="rounded"
                size="large"
                hide-content
              >
                <a-tab-pane v-for="category in categoryKeys" :key="category">
                  <template #title>
                    <a-space size="mini">
                      <span>{{ categoryText(category, 'title') }}</span>
                      <a-badge :count="categoryCount(category)" :max-count="99" />
                    </a-space>
                  </template>
                </a-tab-pane>
              </a-tabs>

              <a-alert
                v-if="normalizedSearch"
                type="info"
                :title="
                  t('admin.systemSettings.searchResults', {
                    count: visibleSettings.length,
                  })
                "
              >
                {{ t('admin.systemSettings.searchHint') }}
              </a-alert>
              <a-alert
                v-else
                type="info"
                :title="categoryText(activeCategory, 'title')"
              >
                {{ categoryText(activeCategory, 'description') }}
              </a-alert>

              <a-grid
                v-if="visibleSettings.length"
                :cols="{ xs: 1, sm: 1, xl: 2 }"
                :col-gap="24"
                :row-gap="12"
              >
                <a-grid-item
                  v-for="setting in visibleSettings"
                  :key="setting.key"
                  :span="{ xs: 1, sm: 1, xl: setting.wide ? 2 : 1 }"
                >
                  <a-form-item
                    :field="setting.control === 'readonly' ? undefined : setting.key"
                    :validate-status="fieldError(setting.key) ? 'error' : undefined"
                    :help="fieldError(setting.key)"
                  >
                    <template #label>
                      <a-space direction="vertical" :size="2">
                        <a-space size="mini" wrap>
                          <a-typography-text bold>
                            {{ fieldLabel(setting.key) }}
                          </a-typography-text>
                          <a-tag
                            v-if="setting.control === 'readonly'"
                            size="small"
                            color="gray"
                          >
                            {{ t('admin.systemSettings.readOnly') }}
                          </a-tag>
                        </a-space>
                        <a-typography-text type="secondary">
                          {{ setting.key }}
                        </a-typography-text>
                      </a-space>
                    </template>

                    <a-select
                      v-if="setting.control === 'boolean'"
                      v-model="form.settings[setting.key]"
                      size="large"
                      long
                    >
                      <a-option :value="setting.enabled_value">
                        {{ t('admin.ui.enabled') }}
                      </a-option>
                      <a-option :value="setting.disabled_value">
                        {{ t('admin.ui.disabled') }}
                      </a-option>
                    </a-select>
                    <a-input-number
                      v-else-if="setting.control === 'number'"
                      :model-value="numberValue(setting.key)"
                      size="large"
                      mode="embed"
                      @update:model-value="updateNumberValue(setting.key, $event)"
                    />
                    <a-textarea
                      v-else-if="setting.control === 'textarea'"
                      v-model="form.settings[setting.key]"
                      size="large"
                      :auto-size="{ minRows: 3, maxRows: 8 }"
                      allow-clear
                    />
                    <a-input-password
                      v-else-if="setting.control === 'password'"
                      v-model="form.settings[setting.key]"
                      size="large"
                      allow-clear
                    />
                    <a-input
                      v-else-if="setting.control === 'readonly'"
                      :model-value="setting.value"
                      size="large"
                      readonly
                    />
                    <a-input
                      v-else
                      v-model="form.settings[setting.key]"
                      size="large"
                      allow-clear
                    />
                  </a-form-item>
                </a-grid-item>
              </a-grid>
              <a-empty
                v-else
                :description="t('admin.systemSettings.noSearchResults')"
              />

              <a-divider />

              <a-space wrap size="medium">
                <a-button
                  type="primary"
                  size="large"
                  html-type="submit"
                  :loading="form.processing"
                >
                  {{ t('admin.systemSettings.save') }}
                </a-button>
                <a-typography-text type="secondary">
                  {{ t('admin.systemSettings.saveHint') }}
                </a-typography-text>
                <a-tag v-if="form.recentlySuccessful" color="green">
                  {{ t('admin.common.saved') }}
                </a-tag>
              </a-space>
            </a-space>
          </a-form>
          <a-empty v-else :description="t('admin.systemSettings.empty')" />
        </a-card>
      </a-col>
    </a-row>
  </a-space>
</template>
