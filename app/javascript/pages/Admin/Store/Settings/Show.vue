<script setup lang="ts">
import { useForm, router } from '@inertiajs/vue3'
import { ref, onBeforeUnmount, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import { confirm } from '@/lib/arcoConfirm'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

export interface StoreSettingItem {
  key: string
  value: string
  label: string
  hint?: string | null
  input_type: 'text' | 'number'
}

export interface ShippingMethodItem {
  code: string
  label: string
  cents: number
  delivery_days_min?: number | null
  delivery_days_max?: number | null
}

export interface LastTestWebhook {
  event_type: string
  status: string
  response_code: number | null
  created_at: string
}

export interface StoreFeatureToggle {
  id: string
  label: string
  description: string
  enabled: boolean
}

const props = defineProps<{
  settings: StoreSettingItem[]
  storeFeatures: StoreFeatureToggle[]
  shippingMethods?: ShippingMethodItem[]
  testWebhookUrl?: string | null
  testAllWebhooksUrl?: string | null
  testWebhookStatusUrl?: string | null
  testWebhookEvents?: string[]
  lastTestWebhook?: LastTestWebhook | null
}>()

const selectedTestEvent = ref(props.testWebhookEvents?.[0] || 'order.test')
const lastTestWebhookDisplay = ref<LastTestWebhook | null>(props.lastTestWebhook ?? null)

const testEventOptions = computed(() =>
  (props.testWebhookEvents || ['order.test']).map((event) => ({ value: event, label: event })),
)

let pollTimer: ReturnType<typeof setInterval> | null = null

onBeforeUnmount(() => {
  if (pollTimer) clearInterval(pollTimer)
})

async function pollWebhookStatus() {
  if (!props.testWebhookStatusUrl) return
  try {
    const response = await fetch(props.testWebhookStatusUrl, { headers: { Accept: 'application/json' } })
    if (!response.ok) return
    const data = await response.json()
    if (data.lastTestWebhook) lastTestWebhookDisplay.value = data.lastTestWebhook
  } catch {
    // Polling is best-effort and should not block settings updates.
  }
}

function startPollingWebhookStatus() {
  if (pollTimer) clearInterval(pollTimer)
  pollTimer = setInterval(pollWebhookStatus, 2000)
  void pollWebhookStatus()
  setTimeout(() => {
    if (pollTimer) clearInterval(pollTimer)
    pollTimer = null
  }, 30000)
}

const form = useForm({
  settings: Object.fromEntries(props.settings.map((setting) => [setting.key, setting.value])),
  store_features: Object.fromEntries(
    (props.storeFeatures || []).map((feature) => [feature.id, feature.enabled]),
  ),
})

const shippingFeatureEnabled = computed(() => form.store_features.shipping === true)
const giftWrapFeatureEnabled = computed(() => form.store_features.gift_wrap === true)

const visibleSettings = computed(() =>
  props.settings.filter((setting) => {
    if (
      !shippingFeatureEnabled.value
      && ['store.free_shipping_min_order_cents', 'store.flat_shipping_cents'].includes(setting.key)
    ) {
      return false
    }
    if (!giftWrapFeatureEnabled.value && setting.key === 'store.gift_wrap_cents') {
      return false
    }
    return true
  }),
)

const shippingMethods = ref(
  (props.shippingMethods || []).map((method) => ({
    code: method.code,
    label: method.label,
    cents: method.cents,
    delivery_days_min: method.delivery_days_min ?? undefined,
    delivery_days_max: method.delivery_days_max ?? undefined,
  })),
)

function addShippingMethod() {
  shippingMethods.value.push({
    code: `method_${shippingMethods.value.length + 1}`,
    label: t('admin.storeSettings.newShippingLabel'),
    cents: 0,
    delivery_days_min: undefined,
    delivery_days_max: undefined,
  })
}

function removeShippingMethod(index: number) {
  shippingMethods.value.splice(index, 1)
}

function fieldError(field: string) {
  return form.errors[field]
}

function submit() {
  form
    .transform((data) => {
      const payload: Record<string, unknown> = { ...data }
      if (shippingFeatureEnabled.value) {
        payload.shipping_methods = shippingMethods.value.map((method) => ({
          code: method.code,
          label: method.label,
          cents: Number(method.cents) || 0,
          delivery_days_min: method.delivery_days_min == null
            ? null
            : Number(method.delivery_days_min),
          delivery_days_max: method.delivery_days_max == null
            ? null
            : Number(method.delivery_days_max),
        }))
      }
      return payload
    })
    .patch(adminRoutes.storeSettings)
}

async function sendTestWebhook() {
  const ok = await confirm({
    title: t('admin.storeSettings.sendWebhookTestTitle'),
    message: t('admin.storeSettings.sendWebhookTestConfirm', { event: selectedTestEvent.value }),
  })
  if (!props.testWebhookUrl || !ok) return
  router.post(
    props.testWebhookUrl,
    { event: selectedTestEvent.value },
    { onSuccess: () => startPollingWebhookStatus() },
  )
}

async function sendTestAllWebhooks() {
  const ok = await confirm({
    title: t('admin.storeSettings.batchWebhookTestTitle'),
    message: t('admin.storeSettings.batchWebhookTestConfirm'),
  })
  if (!props.testAllWebhooksUrl || !ok) return
  router.post(
    props.testAllWebhooksUrl,
    {},
    { onSuccess: () => startPollingWebhookStatus() },
  )
}
</script>

<template>
  <section class="admin-store-settings">
    <a-page-header
      :title="t('admin.storeSettings.title')"
      :subtitle="t('admin.storeSettings.subtitle')"
      :show-back="false"
      class="mb-4 !px-0"
    />

    <a-form
      :model="{ ...form.settings, ...form.store_features }"
      layout="vertical"
      class="max-w-5xl"
      @submit="submit"
    >
      <a-space direction="vertical" fill :size="16">
        <a-card
          :title="t('admin.storeSettings.featureToggles')"
          :bordered="true"
        >
          <template #extra>
            <a-typography-text type="secondary">
              {{ t('admin.storeSettings.featureTogglesHint') }}
            </a-typography-text>
          </template>

          <a-list :bordered="false" :split="true">
            <a-list-item v-for="feature in storeFeatures" :key="feature.id">
              <a-list-item-meta
                :title="feature.label"
                :description="feature.description"
              />
              <template #actions>
                <a-switch v-model="form.store_features[feature.id]" />
              </template>
            </a-list-item>
          </a-list>
        </a-card>

        <a-card
          v-if="shippingFeatureEnabled"
          :title="t('admin.storeSettings.shippingMethods')"
          :bordered="true"
        >
          <template #extra>
            <a-button size="small" @click="addShippingMethod">
              {{ t('admin.storeSettings.addShipping') }}
            </a-button>
          </template>

          <a-alert
            type="info"
            :title="t('admin.storeSettings.shippingHint')"
            class="mb-4"
          />

          <a-space v-if="shippingMethods.length" direction="vertical" fill :size="12">
            <a-card
              v-for="(method, index) in shippingMethods"
              :key="`${method.code}-${index}`"
              :bordered="true"
              size="small"
            >
              <a-grid
                :cols="{ xs: 1, sm: 2, lg: 6 }"
                :col-gap="12"
                :row-gap="4"
                align="end"
              >
                <a-grid-item>
                  <a-form-item :label="t('admin.storeSettings.code')" hide-asterisk>
                    <a-input v-model="method.code" placeholder="standard" />
                  </a-form-item>
                </a-grid-item>
                <a-grid-item :span="{ xs: 1, sm: 1, lg: 2 }">
                  <a-form-item :label="t('admin.storeSettings.label')" hide-asterisk>
                    <a-input v-model="method.label" />
                  </a-form-item>
                </a-grid-item>
                <a-grid-item>
                  <a-form-item :label="t('admin.storeSettings.cents')" hide-asterisk>
                    <a-input-number v-model="method.cents" :min="0" class="w-full" />
                  </a-form-item>
                </a-grid-item>
                <a-grid-item>
                  <a-form-item :label="t('admin.storeSettings.minDays')" hide-asterisk>
                    <a-input-number
                      v-model="method.delivery_days_min"
                      :min="0"
                      class="w-full"
                    />
                  </a-form-item>
                </a-grid-item>
                <a-grid-item>
                  <a-form-item :label="t('admin.storeSettings.maxDays')" hide-asterisk>
                    <a-space>
                      <a-input-number
                        v-model="method.delivery_days_max"
                        :min="0"
                        class="w-full"
                      />
                      <a-button status="danger" size="small" @click="removeShippingMethod(index)">
                        {{ t('admin.ui.delete') }}
                      </a-button>
                    </a-space>
                  </a-form-item>
                </a-grid-item>
              </a-grid>
            </a-card>
          </a-space>
          <a-empty v-else :description="t('admin.storeSettings.emptyShipping')" />
        </a-card>

        <a-card :bordered="true">
          <a-form-item
            v-for="setting in visibleSettings"
            :key="setting.key"
            :field="setting.key"
            :label="setting.label"
            :validate-status="fieldError(setting.key) ? 'error' : undefined"
            :help="fieldError(setting.key) || setting.hint || undefined"
          >
            <a-input
              v-model="form.settings[setting.key]"
              :input-attrs="setting.input_type === 'number' ? { type: 'number', min: 0 } : undefined"
              allow-clear
            />
          </a-form-item>

          <a-space wrap>
            <a-button type="primary" html-type="submit" :loading="form.processing">
              {{ t('admin.storeSettings.save') }}
            </a-button>

            <template v-if="testWebhookUrl">
              <a-select
                v-model="selectedTestEvent"
                :options="testEventOptions"
                class="min-w-48"
              />
              <a-button @click="sendTestWebhook">
                {{ t('admin.storeSettings.sendWebhookTest') }}
              </a-button>
              <a-button v-if="testAllWebhooksUrl" @click="sendTestAllWebhooks">
                {{ t('admin.storeSettings.batchWebhookTest') }}
              </a-button>
            </template>
          </a-space>

          <a-alert
            v-if="lastTestWebhookDisplay"
            type="info"
            show-icon
            class="mt-4"
          >
            {{
              t('admin.storeSettings.lastTest', {
                event: lastTestWebhookDisplay.event_type,
                status: lastTestWebhookDisplay.status,
              })
            }}
            <span v-if="lastTestWebhookDisplay.response_code != null">
              {{
                t('admin.storeSettings.lastTestHttp', {
                  code: lastTestWebhookDisplay.response_code,
                })
              }}
            </span>
            · {{ lastTestWebhookDisplay.created_at }}
          </a-alert>
        </a-card>
      </a-space>
    </a-form>
  </section>
</template>
