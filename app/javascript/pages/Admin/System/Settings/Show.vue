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
}

const props = defineProps<{
  settings: SettingItem[]
}>()

const form = useForm({
  settings: Object.fromEntries(props.settings.map((setting) => [setting.key, setting.value])),
})

function fieldError(key: string) {
  return form.errors[key] || form.errors[`settings.${key}`]
}

function submit() {
  form.patch(adminRoutes.settings)
}
</script>

<template>
  <section class="admin-system-settings">
    <a-page-header
      :title="t('admin.systemSettings.title')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-card class="max-w-3xl" :bordered="true">
      <a-form :model="form.settings" layout="vertical" @submit="submit">
        <a-form-item
          v-for="setting in settings"
          :key="setting.key"
          :field="setting.key"
          :label="setting.key"
          :validate-status="fieldError(setting.key) ? 'error' : undefined"
          :help="fieldError(setting.key)"
        >
          <a-input v-model="form.settings[setting.key]" allow-clear />
        </a-form-item>

        <a-space wrap>
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
    </a-card>

    <a-card
      :title="t('admin.settings')"
      class="mt-4 max-w-3xl"
      :bordered="true"
    >
      <a-space wrap>
        <a-link
          :href="adminRoutes.jobs"
          data-admin-hard-navigation
        >
          {{ t('admin.common.backgroundJobs') }}
        </a-link>
        <a-divider direction="vertical" />
        <a-link href="/health/ready" data-admin-hard-navigation>
          {{ t('admin.common.healthCheck') }}
        </a-link>
      </a-space>
    </a-card>
  </section>
</template>
