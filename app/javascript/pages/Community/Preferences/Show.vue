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
    in_app: boolean
    email: boolean
  }>
}>()

const form = useForm({
  preferences: Object.fromEntries(
    props.preferences.map((pref) => [
      pref.notification_type,
      { in_app: pref.in_app, email: pref.email },
    ])
  ) as Record<string, { in_app: boolean; email: boolean }>,
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

  <PageHeader title="通知偏好" subtitle="管理站内通知与邮件通知" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div
      v-for="pref in preferences"
      :key="pref.notification_type"
      class="rounded-lg border p-4"
    >
      <p class="mb-3 text-sm font-medium">{{ pref.label }}</p>
      <div class="flex flex-wrap gap-6">
        <label class="flex items-center gap-2 text-sm">
          <input
            v-model="form.preferences[pref.notification_type].in_app"
            type="checkbox"
            class="h-4 w-4"
          />
          站内通知
        </label>
        <label class="flex items-center gap-2 text-sm">
          <input
            v-model="form.preferences[pref.notification_type].email"
            type="checkbox"
            class="h-4 w-4"
          />
          邮件通知
        </label>
      </div>
    </div>
    <Button type="submit" :disabled="form.processing">保存</Button>
  </form>
</template>
