<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  preferences: Array<{
    notification_type: string
    label: string
    email: boolean
    in_app: boolean
  }>
}>()

const form = useForm({
  preferences: Object.fromEntries(
    props.preferences.map((pref) => [
      pref.notification_type,
      { email: pref.email, in_app: pref.in_app },
    ])
  ) as Record<string, { email: boolean; in_app: boolean }>,
})

function submit() {
  form.patch(routes.storePreferences)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.preferences.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.preferences.title')" :subtitle="t('commerce.preferences.subtitle')" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div
      v-for="pref in preferences"
      :key="pref.notification_type"
      class="rounded-lg border p-4"
    >
      <p class="mb-3 text-sm font-medium">{{ pref.label }}</p>
      <div class="flex flex-wrap gap-4">
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.preferences[pref.notification_type].email" />
          {{ t('commerce.preferences.email') }}
        </label>
        <label class="flex items-center gap-2 text-sm">
          <Checkbox v-model="form.preferences[pref.notification_type].in_app" />
          {{ t('commerce.preferences.inApp') }}
        </label>
      </div>
    </div>
    <Button type="submit" :disabled="form.processing">{{ t('commerce.preferences.save') }}</Button>
    <Button as-child variant="outline">
      <Link :href="routes.storeOrders">{{ t('commerce.preferences.backToOrders') }}</Link>
    </Button>
  </form>
</template>
