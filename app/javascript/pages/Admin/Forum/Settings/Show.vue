<script setup lang="ts">
import { Link, useForm, router } from '@inertiajs/vue3'
import { ref, onBeforeUnmount, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface ForumSettingItem {
  key: string
  value: string
  label: string
  hint?: string | null
  input_type: 'text' | 'number' | 'boolean' | 'password'
  sensitive?: boolean
  configured?: boolean
}

export interface SavedSearchForTest {
  id: number
  name: string
}

export interface LastTestWebhook {
  event_type: string
  status: string
  response_code: number | null
  created_at: string
}

const props = defineProps<{
  settings: ForumSettingItem[]
  testWebhookUrl?: string | null
  testAllWebhooksUrl?: string | null
  testEventWebhookUrl?: string | null
  testAllEventWebhooksUrl?: string | null
  testEventWebhookEvents?: string[]
  testWebhookStatusUrl?: string | null
  savedSearchesForTest?: SavedSearchForTest[]
  lastTestWebhook?: LastTestWebhook | null
  lastTestEventWebhook?: LastTestWebhook | null
}>()

const selectedSavedSearchId = ref<string>('')
const selectedEventType = ref(props.testEventWebhookEvents?.[0] || 'topic.created')
const lastTestWebhookDisplay = ref<LastTestWebhook | null>(props.lastTestWebhook ?? null)
const lastTestEventWebhookDisplay = ref<LastTestWebhook | null>(props.lastTestEventWebhook ?? null)
let pollTimer: ReturnType<typeof setInterval> | null = null

onBeforeUnmount(() => {
  if (pollTimer) clearInterval(pollTimer)
})

async function pollWebhookStatus() {
  if (!props.testWebhookStatusUrl) return
  try {
    const response = await fetch(props.testWebhookStatusUrl, { headers: { Accept: 'application/json' } })
    if (!response.ok) return
    const data = await response.json()
    if (data.lastTestWebhook) lastTestWebhookDisplay.value = data.lastTestWebhook
    if (data.lastTestEventWebhook) lastTestEventWebhookDisplay.value = data.lastTestEventWebhook
  } catch {
    // ignore polling errors
  }
}

function startPollingWebhookStatus() {
  if (pollTimer) clearInterval(pollTimer)
  pollTimer = setInterval(pollWebhookStatus, 2000)
  void pollWebhookStatus()
  setTimeout(() => {
    if (pollTimer) clearInterval(pollTimer)
    pollTimer = null
  }, 30000)
}

const form = useForm({
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

const savedSearchOptions = computed(() => [
  { value: '', label: t('admin.forumSettings.genericPayload') },
  ...(props.savedSearchesForTest || []).map((search) => ({ value: String(search.id), label: search.name })),
])

const eventWebhookOptions = computed(() =>
  (props.testEventWebhookEvents || ['topic.created']).map((event) => ({ value: event, label: event })),
)

function submit() {
  form.patch(adminRoutes.forumSettings)
}

async function sendTestWebhook() {
  const ok = await confirm({
    title: t('admin.forumSettings.sendWebhookTestTitle'),
    message: t('admin.forumSettings.sendWebhookTestConfirm'),
  })
  if (!props.testWebhookUrl || !ok) return
  const data = selectedSavedSearchId.value ? { saved_search_id: selectedSavedSearchId.value } : {}
  router.post(props.testWebhookUrl, data, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}

async function sendTestAllWebhooks() {
  const ok = await confirm({
    title: t('admin.forumSettings.batchWebhookTestTitle'),
    message: t('admin.forumSettings.batchWebhookTestConfirm'),
  })
  if (!props.testAllWebhooksUrl || !ok) return
  router.post(props.testAllWebhooksUrl, {}, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}

async function sendTestEventWebhook() {
  const ok = await confirm({
    title: t('admin.forumSettings.sendEventWebhookTestTitle'),
    message: t('admin.forumSettings.sendEventWebhookTestConfirm', { event: selectedEventType.value }),
  })
  if (!props.testEventWebhookUrl || !ok) return
  router.post(props.testEventWebhookUrl, { event: selectedEventType.value }, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}

async function sendTestAllEventWebhooks() {
  const ok = await confirm({
    title: t('admin.forumSettings.batchEventWebhookTestTitle'),
    message: t('admin.forumSettings.batchEventWebhookTestConfirm'),
  })
  if (!props.testAllEventWebhooksUrl || !ok) return
  router.post(props.testAllEventWebhooksUrl, {}, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}
</script>

<template>
  <a-page-header
    :title="t('admin.forumSettings.title')"
    :subtitle="t('admin.forumSettings.subtitle')"
    :show-back="false"
    class="mb-4 !px-0"
  />

  <form class="max-w-3xl space-y-4" @submit.prevent="submit">
    <a-card :bordered="true">
      <a-space direction="vertical" fill :size="16">
        <a-card
          v-for="setting in settings"
          :key="setting.key"
          size="small"
          :bordered="true"
        >
          <p class="mb-1 text-sm font-medium">{{ setting.label }}</p>
          <p v-if="setting.hint" class="mb-3 text-xs text-[var(--color-text-3)]">
            {{ setting.hint }}
          </p>
          <a-checkbox
            v-if="setting.input_type === 'boolean'"
            :model-value="['true', '1'].includes(form.settings[setting.key])"
            @change="(value: boolean) => { form.settings[setting.key] = value ? 'true' : 'false' }"
          >
            {{ t('admin.common.enable') }}
          </a-checkbox>
          <a-input-password
            v-else-if="setting.input_type === 'password'"
            v-model="form.settings[setting.key]"
            :placeholder="setting.configured ? '••••••••' : undefined"
            allow-clear
          />
          <a-input
            v-else
            v-model="form.settings[setting.key]"
            :input-attrs="setting.input_type === 'number' ? { type: 'number' } : undefined"
            allow-clear
          />
        </a-card>

        <div>
          <a-button html-type="submit" type="primary" :loading="form.processing">
            {{ t('admin.forumSettings.save') }}
          </a-button>
        </div>
      </a-space>
    </a-card>

    <a-card
      v-if="testWebhookUrl"
      :title="t('admin.forumSettings.savedSearchWebhookTests')"
      :bordered="true"
    >
      <a-space wrap :size="[8, 8]">
        <a-select
          v-if="savedSearchesForTest?.length"
          v-model="selectedSavedSearchId"
          :options="savedSearchOptions"
          size="small"
          class="min-w-48"
        />
        <a-button type="outline" size="small" @click="sendTestWebhook">
          {{ t('admin.forumSettings.sendWebhookTest') }}
        </a-button>
        <a-button
          v-if="testAllWebhooksUrl && savedSearchesForTest?.length"
          type="outline"
          size="small"
          @click="sendTestAllWebhooks"
        >
          {{ t('admin.forumSettings.batchWebhookTest') }}
        </a-button>
      </a-space>
      <a-alert v-if="lastTestWebhookDisplay" class="mt-3" type="info">
        {{ t('admin.forumSettings.lastTest', { event: lastTestWebhookDisplay.event_type, status: lastTestWebhookDisplay.status }) }}
        <span v-if="lastTestWebhookDisplay.response_code != null">
          {{ t('admin.forumSettings.lastTestHttp', { code: lastTestWebhookDisplay.response_code }) }}
        </span>
        · {{ lastTestWebhookDisplay.created_at }}
      </a-alert>
    </a-card>

    <a-card
      v-if="testEventWebhookUrl"
      :title="t('admin.forumSettings.eventWebhookTests')"
      :bordered="true"
    >
      <a-space wrap :size="[8, 8]">
        <a-select
          v-model="selectedEventType"
          :options="eventWebhookOptions"
          size="small"
          class="min-w-48"
        />
        <a-button type="outline" size="small" @click="sendTestEventWebhook">
          {{ t('admin.forumSettings.sendEventWebhookTest') }}
        </a-button>
        <a-button
          v-if="testAllEventWebhooksUrl"
          type="outline"
          size="small"
          @click="sendTestAllEventWebhooks"
        >
          {{ t('admin.forumSettings.batchEventWebhookTest') }}
        </a-button>
      </a-space>
      <a-alert v-if="lastTestEventWebhookDisplay" class="mt-3" type="info">
        {{ t('admin.forumSettings.lastTest', { event: lastTestEventWebhookDisplay.event_type, status: lastTestEventWebhookDisplay.status }) }}
        <span v-if="lastTestEventWebhookDisplay.response_code != null">
          {{ t('admin.forumSettings.lastTestHttp', { code: lastTestEventWebhookDisplay.response_code }) }}
        </span>
        · {{ lastTestEventWebhookDisplay.created_at }}
      </a-alert>
      <Link
        :href="adminRoutes.forumEventWebhookDeliveries"
        class="mt-3 inline-block text-xs text-[rgb(var(--primary-6))] no-underline hover:underline"
      >
        {{ t('admin.forumSettings.viewEventDeliveries') }}
      </Link>
    </a-card>
  </form>
</template>
