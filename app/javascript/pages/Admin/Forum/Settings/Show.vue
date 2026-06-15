<script setup lang="ts">
import { useForm, router } from '@inertiajs/vue3'
import { ref, onBeforeUnmount } from 'vue'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

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
  testWebhookStatusUrl?: string | null
  savedSearchesForTest?: SavedSearchForTest[]
  lastTestWebhook?: LastTestWebhook | null
}>()

const selectedSavedSearchId = ref<string>('')
const lastTestWebhookDisplay = ref<LastTestWebhook | null>(props.lastTestWebhook ?? null)
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

function submit() {
  form.patch(adminRoutes.forumSettings)
}

function sendTestWebhook() {
  if (!props.testWebhookUrl || !confirm('向配置的 Webhook URL 发送 saved_search.match 测试事件？')) return
  const data = selectedSavedSearchId.value ? { saved_search_id: selectedSavedSearchId.value } : {}
  router.post(props.testWebhookUrl, data, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}
</script>

<template>
  <PageHeader title="论坛设置" subtitle="私信、警告、反应与主题行为（对标 Discourse / XenForo 站点选项）" />

  <form class="max-w-xl space-y-4" @submit.prevent="submit">
    <div v-for="setting in settings" :key="setting.key" class="rounded-lg border p-4 space-y-2">
      <Label :for="setting.key" class="text-sm font-medium">{{ setting.label }}</Label>
      <p v-if="setting.hint" class="text-xs text-muted-foreground">{{ setting.hint }}</p>
      <label v-if="setting.input_type === 'boolean'" class="flex items-center gap-2 text-sm">
        <input
          :id="setting.key"
          v-model="form.settings[setting.key]"
          type="checkbox"
          class="h-4 w-4 rounded border"
          true-value="true"
          false-value="false"
        />
        启用
      </label>
      <Input v-else :id="setting.key" v-model="form.settings[setting.key]" />
    </div>
    <Button type="submit" :disabled="form.processing">保存论坛设置</Button>
    <template v-if="testWebhookUrl">
      <select
        v-if="savedSearchesForTest?.length"
        v-model="selectedSavedSearchId"
        class="ml-2 h-9 rounded-md border border-input bg-transparent px-3 text-sm"
      >
        <option value="">通用测试载荷</option>
        <option v-for="search in savedSearchesForTest" :key="search.id" :value="String(search.id)">
          {{ search.name }}
        </option>
      </select>
      <Button type="button" variant="outline" class="ml-2" @click="sendTestWebhook">
        发送 Webhook 测试
      </Button>
      <p v-if="lastTestWebhookDisplay" class="mt-2 text-xs text-muted-foreground">
        最近测试：{{ lastTestWebhookDisplay.event_type }} · {{ lastTestWebhookDisplay.status }}
        <span v-if="lastTestWebhookDisplay.response_code != null"> · HTTP {{ lastTestWebhookDisplay.response_code }}</span>
        · {{ lastTestWebhookDisplay.created_at }}
      </p>
    </template>
  </form>
</template>
