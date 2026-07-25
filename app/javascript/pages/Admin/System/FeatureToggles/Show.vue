<script setup lang="ts">
import { computed, ref } from 'vue'
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
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
  <section class="admin-system-feature-toggles">
    <a-page-header
      :title="t('admin.featureToggles.title')"
      :subtitle="t('admin.featureToggles.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-alert
      v-if="localError"
      type="error"
      :title="localError"
      show-icon
      closable
      class="mb-4 max-w-3xl"
      @close="localError = ''"
    />

    <a-form
      :model="form.features"
      layout="vertical"
      class="max-w-3xl"
      @submit="submit"
    >
      <a-space direction="vertical" fill :size="12">
        <a-card
          v-for="feature in features"
          :key="feature.id"
          :bordered="true"
          hoverable
        >
          <div class="flex items-start justify-between gap-6">
            <a-space direction="vertical" :size="4">
              <a-typography-title :heading="6" class="!m-0">
                {{ feature.label }}
              </a-typography-title>
              <a-typography-text type="secondary">
                {{ feature.description }}
              </a-typography-text>
            </a-space>

            <a-space class="shrink-0">
              <a-tag :color="form.features[feature.id] ? 'green' : 'gray'">
                {{ form.features[feature.id] ? t('admin.ui.enabled') : t('admin.ui.disabled') }}
              </a-tag>
              <a-switch v-model="form.features[feature.id]" />
            </a-space>
          </div>
        </a-card>
      </a-space>

      <a-alert
        v-if="portalBothDisabled"
        type="warning"
        :title="t('admin.featureToggles.portalBothDisabled')"
        show-icon
        class="mt-4"
      />

      <a-space class="mt-4" wrap>
        <a-button
          type="primary"
          html-type="submit"
          :loading="form.processing"
          :disabled="portalBothDisabled"
        >
          {{ t('admin.featureToggles.saveToggles') }}
        </a-button>
        <a-tag v-if="form.recentlySuccessful" color="green">
          {{ t('admin.common.saved') }}
        </a-tag>
      </a-space>
    </a-form>
  </section>
</template>
