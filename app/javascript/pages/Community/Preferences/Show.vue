<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Label from '@/components/ui/Label.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  preferences: Array<{
    notification_type: string
    label: string
    enabled: boolean
  }>
}>()

const form = useForm({
  preferences: Object.fromEntries(
    props.preferences.map((p) => [p.notification_type, p.enabled])
  ) as Record<string, boolean>,
})

function submit() {
  form.patch(routes.forumPreferences)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '通知偏好', current: true },
  ]" />

  <PageHeader title="通知偏好" subtitle="管理站内通知类型" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <label
      v-for="pref in preferences"
      :key="pref.notification_type"
      class="flex items-center gap-3 rounded-lg border p-4"
    >
      <input
        v-model="form.preferences[pref.notification_type]"
        type="checkbox"
        class="h-4 w-4"
      />
      <span class="text-sm font-medium">{{ pref.label }}</span>
    </label>
    <Button type="submit" :disabled="form.processing">保存</Button>
  </form>
</template>
