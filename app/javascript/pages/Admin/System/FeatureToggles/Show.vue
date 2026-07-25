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
  <a-space direction="vertical" :size="20" fill>
    <a-page-header
      :title="t('admin.featureToggles.title')"
      :subtitle="t('admin.featureToggles.subtitle')"
      :show-back="false"
    />

    <a-row justify="center">
      <a-col :xs="24" :xl="22">
        <a-card :bordered="true">
          <a-form
            :model="form.features"
            layout="vertical"
            @submit="submit"
          >
            <a-space direction="vertical" :size="20" fill>
              <a-alert
                v-if="localError"
                type="error"
                :title="localError"
                show-icon
                closable
                @close="localError = ''"
              />

              <a-grid
                v-if="features.length"
                :cols="{ xs: 1, lg: 2 }"
                :col-gap="16"
                :row-gap="16"
              >
                <a-grid-item v-for="feature in features" :key="feature.id">
                  <a-card size="small" :bordered="true" hoverable>
                    <a-row align="center" justify="space-between" :gutter="[16, 12]">
                      <a-col flex="1" :style="{ minWidth: 0 }">
                        <a-space direction="vertical" :size="6" fill>
                          <a-typography-text bold>
                            {{ feature.label }}
                          </a-typography-text>
                          <a-typography-paragraph
                            type="secondary"
                            :style="{ marginBottom: 0 }"
                          >
                            {{ feature.description }}
                          </a-typography-paragraph>
                        </a-space>
                      </a-col>
                      <a-col flex="none">
                        <a-switch
                          v-model="form.features[feature.id]"
                          :aria-label="feature.label"
                          :checked-text="t('admin.ui.enabled')"
                          :unchecked-text="t('admin.ui.disabled')"
                        />
                      </a-col>
                    </a-row>
                  </a-card>
                </a-grid-item>
              </a-grid>
              <a-empty v-else :description="t('admin.featureToggles.empty')" />

              <a-alert
                v-if="portalBothDisabled"
                type="warning"
                :title="t('admin.featureToggles.portalBothDisabled')"
                show-icon
              />

              <a-divider />

              <a-space wrap size="medium">
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
            </a-space>
          </a-form>
        </a-card>
      </a-col>
    </a-row>
  </a-space>
</template>
