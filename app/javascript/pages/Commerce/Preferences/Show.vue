<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const props = defineProps<{
  preferences: Array<{
    notification_type: string
    label: string
    email: boolean
  }>
}>()

const form = useForm({
  preferences: Object.fromEntries(
    props.preferences.map((pref) => [pref.notification_type, { email: pref.email }])
  ) as Record<string, { email: boolean }>,
})

function submit() {
  form.patch(routes.storePreferences)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '邮件偏好', current: true },
  ]" />

  <PageHeader title="商城邮件偏好" subtitle="管理订单相关邮件通知" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <label
      v-for="pref in preferences"
      :key="pref.notification_type"
      class="flex items-center gap-3 rounded-lg border p-4"
    >
      <input
        v-model="form.preferences[pref.notification_type].email"
        type="checkbox"
        class="h-4 w-4"
      />
      <span class="text-sm font-medium">{{ pref.label }}</span>
    </label>
    <Button type="submit" :disabled="form.processing">保存</Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">返回订单</Link>
    </Button>
  </form>
</template>
