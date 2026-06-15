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
  digest_frequency: string
  digest_watched_only?: boolean
  digest_options: Array<{ value: string; label: string }>
}>()

const form = useForm({
  preferences: Object.fromEntries(
    props.preferences.map((pref) => [
      pref.notification_type,
      { in_app: pref.in_app, email: pref.email },
    ])
  ) as Record<string, { in_app: boolean; email: boolean }>,
  digest_frequency: props.digest_frequency,
  digest_watched_only: props.digest_watched_only ?? false,
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

    <div class="rounded-lg border p-4">
      <Label for="digest" class="mb-2 block text-sm font-medium">邮件摘要</Label>
      <select id="digest" v-model="form.digest_frequency" class="h-9 w-full rounded-md border px-2 text-sm">
        <option v-for="opt in digest_options" :key="opt.value" :value="opt.value">{{ opt.label }}</option>
      </select>
      <p class="mt-2 text-xs text-muted-foreground">摘要将汇总未读的论坛通知，减少即时邮件打扰。</p>
      <label v-if="form.digest_frequency !== 'none'" class="mt-3 flex items-center gap-2 text-sm">
        <input v-model="form.digest_watched_only" type="checkbox">
        仅包含我关注的分区/主题/标签
      </label>
    </div>

    <Button type="submit" :disabled="form.processing">保存</Button>
  </form>
</template>
