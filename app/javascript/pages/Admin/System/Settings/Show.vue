<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
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
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

function submit() {
  form.patch(adminRoutes.settings)
}
</script>

<template>
  <PageHeader :title="t('admin.systemSettings.title')" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div v-for="setting in settings" :key="setting.key" class="space-y-2">
      <Label :for="setting.key">{{ setting.key }}</Label>
      <Input :id="setting.key" v-model="form.settings[setting.key]" />
    </div>
    <Button type="submit" :disabled="form.processing">{{ t('admin.systemSettings.save') }}</Button>
  </form>

  <p class="mt-6 text-sm text-muted-foreground">
    <a :href="adminRoutes.jobs" class="hover:underline">{{ t('admin.common.backgroundJobs') }}</a>
    ·
    <a href="/health/ready" class="hover:underline">{{ t('admin.common.healthCheck') }}</a>
  </p>
</template>
