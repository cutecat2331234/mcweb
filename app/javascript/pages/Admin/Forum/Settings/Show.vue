<script setup lang="ts">
import { useForm, router } from '@inertiajs/vue3'
import { ref, onBeforeUnmount, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { confirm } from '@/lib/useConfirm'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface ForumSettingItem {
  key: string
  value: string
  label: string
  hint?: string | null
  input_type: 'text' | 'boolean'
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
  <PageHeader :title="t('admin.forumSettings.title')" :subtitle="t('admin.forumSettings.subtitle')" />

  <form class="max-w-xl space-y-4" @submit.prevent="submit">
    <div v-for="setting in settings" :key="setting.key" class="rounded-lg border p-4 space-y-2">
      <Label :for="setting.key" class="text-sm font-medium">{{ setting.label }}</Label>
      <p v-if="setting.hint" class="text-xs text-muted-foreground">{{ setting.hint }}</p>
      <label v-if="setting.input_type === 'boolean'" class="flex items-center gap-2 text-sm">
        <Checkbox
          :id="setting.key"
          :model-value="form.settings[setting.key] === 'true'"
          @update:model-value="(v) => { form.settings[setting.key] = v ? 'true' : 'false' }"
        />
        {{ t('admin.common.enable') }}
      </label>
      <Input v-else :id="setting.key" v-model="form.settings[setting.key]" />
    </div>
    <Button type="submit" :disabled="form.processing">{{ t('admin.forumSettings.save') }}</Button>
    <div v-if="testWebhookUrl" class="rounded-lg border p-4 space-y-2">
      <p class="text-sm font-medium">{{ t('admin.forumSettings.savedSearchWebhookTests') }}</p>
      <div class="flex flex-wrap items-center gap-2">
        <Select
          v-if="savedSearchesForTest?.length"
          v-model="selectedSavedSearchId"
          :options="savedSearchOptions"
          size="sm"
        />
        <Button type="button" variant="outline" size="sm" @click="sendTestWebhook">
          {{ t('admin.forumSettings.sendWebhookTest') }}
        </Button>
        <Button
          v-if="testAllWebhooksUrl && savedSearchesForTest?.length"
          type="button"
          variant="outline"
          size="sm"
          @click="sendTestAllWebhooks"
        >
          {{ t('admin.forumSettings.batchWebhookTest') }}
        </Button>
      </div>
      <p v-if="lastTestWebhookDisplay" class="text-xs text-muted-foreground">
        {{ t('admin.forumSettings.lastTest', { event: lastTestWebhookDisplay.event_type, status: lastTestWebhookDisplay.status }) }}
        <span v-if="lastTestWebhookDisplay.response_code != null">{{ t('admin.forumSettings.lastTestHttp', { code: lastTestWebhookDisplay.response_code }) }}</span>
        · {{ lastTestWebhookDisplay.created_at }}
      </p>
    </div>
    <div v-if="testEventWebhookUrl" class="rounded-lg border p-4 space-y-2">
      <p class="text-sm font-medium">{{ t('admin.forumSettings.eventWebhookTests') }}</p>
      <div class="flex flex-wrap items-center gap-2">
        <Select v-model="selectedEventType" :options="eventWebhookOptions" size="sm" />
        <Button type="button" variant="outline" size="sm" @click="sendTestEventWebhook">
          {{ t('admin.forumSettings.sendEventWebhookTest') }}
        </Button>
        <Button
          v-if="testAllEventWebhooksUrl"
          type="button"
          variant="outline"
          size="sm"
          @click="sendTestAllEventWebhooks"
        >
          {{ t('admin.forumSettings.batchEventWebhookTest') }}
        </Button>
      </div>
      <p v-if="lastTestEventWebhookDisplay" class="text-xs text-muted-foreground">
        {{ t('admin.forumSettings.lastTest', { event: lastTestEventWebhookDisplay.event_type, status: lastTestEventWebhookDisplay.status }) }}
        <span v-if="lastTestEventWebhookDisplay.response_code != null">{{ t('admin.forumSettings.lastTestHttp', { code: lastTestEventWebhookDisplay.response_code }) }}</span>
        · {{ lastTestEventWebhookDisplay.created_at }}
      </p>
      <a :href="adminRoutes.forumEventWebhookDeliveries" class="text-xs text-muted-foreground hover:underline">
        {{ t('admin.forumSettings.viewEventDeliveries') }}
      </a>
    </div>
  </form>
</template>
