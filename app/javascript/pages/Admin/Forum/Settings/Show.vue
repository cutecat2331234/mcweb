<script setup lang="ts">
import { useForm, router } from '@inertiajs/vue3'
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

const props = defineProps<{
  settings: ForumSettingItem[]
  testWebhookUrl?: string | null
}>()

const form = useForm({
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

function submit() {
  form.patch(adminRoutes.forumSettings)
}

function sendTestWebhook() {
  if (!props.testWebhookUrl || !confirm('向配置的 Webhook URL 发送 saved_search.match 测试事件？')) return
  router.post(props.testWebhookUrl)
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
    <Button
      v-if="testWebhookUrl"
      type="button"
      variant="outline"
      class="ml-2"
      @click="sendTestWebhook"
    >
      发送 Webhook 测试
    </Button>
  </form>
</template>
