<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

export interface SettingItem {
  key: string
  value: string
}

const props = defineProps<{
  settings: SettingItem[]
}>()

const form = useForm({
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

function submit() {
  form.patch(adminRoutes.settings)
}
</script>

<template>
  <PageHeader title="系统设置" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div v-for="setting in settings" :key="setting.key" class="space-y-2">
      <Label :for="setting.key">{{ setting.key }}</Label>
      <Input :id="setting.key" v-model="form.settings[setting.key]" />
    </div>
    <Button type="submit" :disabled="form.processing">保存设置</Button>
  </form>

  <p class="mt-6 text-sm text-muted-foreground">
    <a :href="adminRoutes.jobs" class="hover:underline">后台任务</a>
    ·
    <a href="/health/ready" class="hover:underline">健康检查</a>
  </p>
</template>
