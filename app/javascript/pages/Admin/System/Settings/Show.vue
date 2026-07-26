<script setup lang="ts">
import { computed, type Component } from 'vue'
import { Link, router, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import {
  IconApps,
  IconBook,
  IconCloud,
  IconCommand,
  IconDashboard,
  IconExperiment,
  IconHome,
  IconLink,
  IconLock,
  IconSafe,
  IconSettings,
  IconStorage,
  IconThunderbolt,
} from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'

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

const props = defineProps<{
  sections: SettingsSection[]
  basicSettings: {
    site_name: string
    site_url: string
  }
  formErrors?: Record<string, string>
  updateUrl: string
}>()

const { t } = useI18n()
const form = useForm({
  basic_settings: {
    site_name: props.basicSettings.site_name,
    site_url: props.basicSettings.site_url,
  },
})

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

function fieldError(field: 'site_name' | 'site_url') {
  const code = props.formErrors?.[field]
  if (code) return t(`admin.systemSettings.errors.${code}`)

  return form.errors[`basic_settings.${field}`]
}

function submitBasicSettings() {
  form.patch(props.updateUrl, {
    preserveScroll: true,
  })
}
</script>

<template>
  <section class="admin-system-settings">
    <a-page-header
      :title="t('admin.systemSettings.title')"
      :subtitle="t('admin.systemSettings.subtitle')"
      :show-back="false"
      class="mb-5 !px-0"
    >
      <template #extra>
        <a-space wrap>
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
      class="mb-5"
    />

    <a-card
      :title="t('admin.systemSettings.basicTitle')"
      :bordered="true"
      class="mb-5"
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
        :model="form.basic_settings"
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
              :help="fieldError('site_name') || t('admin.systemSettings.siteNameHint')"
              :validate-status="fieldError('site_name') ? 'error' : undefined"
            >
              <a-input
                v-model="form.basic_settings.site_name"
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
              :help="fieldError('site_url') || t('admin.systemSettings.siteUrlHint')"
              :validate-status="fieldError('site_url') ? 'error' : undefined"
            >
              <a-input
                v-model="form.basic_settings.site_url"
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
            :loading="form.processing"
          >
            {{ t('admin.systemSettings.saveBasic') }}
          </a-button>
          <a-tag v-if="form.recentlySuccessful" color="green">
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

    <a-card :bordered="false" class="mt-5">
      <a-space wrap>
        <a-tag color="green">
          {{ t('admin.systemSettings.visibleEntryCount', { count: entryCount }) }}
        </a-tag>
        <a-typography-text type="secondary">
          {{ t('admin.systemSettings.permissionNotice') }}
        </a-typography-text>
      </a-space>
    </a-card>
  </section>
</template>
