<script setup lang="ts">
import { computed, ref } from 'vue'
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Alert from '@/components/ui/Alert.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface FeatureToggleItem {
  id: string
  label: string
  description: string
  enabled: boolean
}

const props = defineProps<{
  features: FeatureToggleItem[]
}>()

const form = useForm({
  features: Object.fromEntries(props.features.map((feature) => [feature.id, feature.enabled])),
})

const localError = ref('')

const portalBothDisabled = computed(() => !form.features.forum && !form.features.store)

function submit() {
  localError.value = ''
  if (portalBothDisabled.value) {
    localError.value = t('admin.featureToggles.portalRequired')
    return
  }
  form.patch(adminRoutes.featureToggles)
}
</script>

<template>
  <PageHeader
    :title="t('admin.featureToggles.title')"
    :subtitle="t('admin.featureToggles.subtitle')"
  />

  <Alert v-if="localError" variant="destructive" class="mb-4 max-w-2xl">
    {{ localError }}
  </Alert>

  <form class="max-w-2xl space-y-4" @submit.prevent="submit">
    <div
      v-for="feature in features"
      :key="feature.id"
      class="flex items-start justify-between gap-4 rounded-lg border border-border bg-card p-4"
    >
      <div class="min-w-0 space-y-1">
        <p class="font-medium leading-none">{{ feature.label }}</p>
        <p class="text-sm text-muted-foreground">{{ feature.description }}</p>
      </div>
      <label class="flex shrink-0 cursor-pointer items-center gap-2 text-sm">
        <Checkbox v-model="form.features[feature.id]" />
        <span>{{ form.features[feature.id] ? t('admin.ui.enabled') : t('admin.ui.disabled') }}</span>
      </label>
    </div>

    <p v-if="portalBothDisabled" class="text-sm text-destructive">
      {{ t('admin.featureToggles.portalBothDisabled') }}
    </p>

    <div class="flex flex-wrap items-center justify-end gap-3 pt-2 sm:justify-start">
      <Button type="submit" :disabled="form.processing || portalBothDisabled">{{ t('admin.featureToggles.saveToggles') }}</Button>
      <p v-if="form.recentlySuccessful" class="text-sm text-muted-foreground">{{ t('admin.common.saved') }}</p>
    </div>
  </form>
</template>
