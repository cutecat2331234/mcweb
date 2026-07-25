<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface SettingItem {
  key: string
  value: string
  control: 'text' | 'boolean'
  enabled_value: string
  disabled_value: string
}

const props = defineProps<{
  settings: SettingItem[]
}>()

const form = useForm<any>({
  settings: Object.fromEntries(props.settings.map((setting) => [setting.key, setting.value])),
})

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
      <a-col :xs="24" :lg="22" :xl="20">
        <a-card
          :title="t('admin.systemSettings.configuration')"
          :bordered="true"
        >
          <template #extra>
            <a-tag color="arcoblue" round>{{ settings.length }}</a-tag>
          </template>

          <a-form
            v-if="settings.length"
            :model="form.settings"
            layout="vertical"
            @submit="submit"
          >
            <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="20">
              <a-grid-item v-for="setting in settings" :key="setting.key">
                <a-form-item
                  :field="setting.key"
                  :label="setting.key"
                  :validate-status="fieldError(setting.key) ? 'error' : undefined"
                  :help="fieldError(setting.key)"
                >
                  <a-select
                    v-if="setting.control === 'boolean'"
                    v-model="form.settings[setting.key]"
                    long
                  >
                    <a-option :value="setting.enabled_value">
                      {{ t('admin.ui.enabled') }}
                    </a-option>
                    <a-option :value="setting.disabled_value">
                      {{ t('admin.ui.disabled') }}
                    </a-option>
                  </a-select>
                  <a-input
                    v-else
                    v-model="form.settings[setting.key]"
                    allow-clear
                  />
                </a-form-item>
              </a-grid-item>
            </a-grid>

            <a-divider />

            <a-space wrap size="medium">
              <a-button
                type="primary"
                html-type="submit"
                :loading="form.processing"
              >
                {{ t('admin.systemSettings.save') }}
              </a-button>
              <a-tag v-if="form.recentlySuccessful" color="green">
                {{ t('admin.common.saved') }}
              </a-tag>
            </a-space>
          </a-form>
          <a-empty v-else :description="t('admin.systemSettings.empty')" />
        </a-card>
      </a-col>
    </a-row>
  </a-space>
</template>
