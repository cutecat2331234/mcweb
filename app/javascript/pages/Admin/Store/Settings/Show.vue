<script setup lang="ts">
import { useForm, router } from '@inertiajs/vue3'
import { ref, onBeforeUnmount, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import { confirm } from '@/lib/useConfirm'
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

const props = defineProps<{
  settings: StoreSettingItem[]
  shippingMethods: ShippingMethodItem[]
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
    // ignore polling errors
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
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

const shippingMethods = ref(
  props.shippingMethods.map((method) => ({
    code: method.code,
    label: method.label,
    cents: method.cents,
    delivery_days_min: method.delivery_days_min ?? '',
    delivery_days_max: method.delivery_days_max ?? '',
  }))
)

function addShippingMethod() {
  shippingMethods.value.push({
    code: `method_${shippingMethods.value.length + 1}`,
    label: t('admin.storeSettings.newShippingLabel'),
    cents: 0,
    delivery_days_min: '',
    delivery_days_max: '',
  })
}

function removeShippingMethod(index: number) {
  shippingMethods.value.splice(index, 1)
}

function submit() {
  form
    .transform((data) => ({
      ...data,
      shipping_methods: shippingMethods.value.map((method) => ({
        code: method.code,
        label: method.label,
        cents: Number(method.cents) || 0,
        delivery_days_min: method.delivery_days_min === '' ? null : Number(method.delivery_days_min),
        delivery_days_max: method.delivery_days_max === '' ? null : Number(method.delivery_days_max),
      })),
    }))
    .patch(adminRoutes.storeSettings)
}

async function sendTestWebhook() {
  const ok = await confirm({
    title: t('admin.storeSettings.sendWebhookTestTitle'),
    message: t('admin.storeSettings.sendWebhookTestConfirm', { event: selectedTestEvent.value }),
  })
  if (!props.testWebhookUrl || !ok) return
  router.post(props.testWebhookUrl, { event: selectedTestEvent.value }, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}

async function sendTestAllWebhooks() {
  const ok = await confirm({
    title: t('admin.storeSettings.batchWebhookTestTitle'),
    message: t('admin.storeSettings.batchWebhookTestConfirm'),
  })
  if (!props.testAllWebhooksUrl || !ok) return
  router.post(props.testAllWebhooksUrl, {}, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}
</script>

<template>
  <PageHeader :title="t('admin.storeSettings.title')" :subtitle="t('admin.storeSettings.subtitle')" />

  <form class="max-w-3xl space-y-6" @submit.prevent="submit">
    <section class="space-y-4 rounded-lg border p-4">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h2 class="text-sm font-semibold">{{ t('admin.storeSettings.shippingMethods') }}</h2>
          <p class="text-xs text-muted-foreground">{{ t('admin.storeSettings.shippingHint') }}</p>
        </div>
        <Button type="button" size="sm" variant="outline" @click="addShippingMethod">{{ t('admin.storeSettings.addShipping') }}</Button>
      </div>

      <div v-if="shippingMethods.length" class="space-y-3">
        <div
          v-for="(method, index) in shippingMethods"
          :key="`${method.code}-${index}`"
          class="grid gap-2 rounded-md border p-3 sm:grid-cols-2 lg:grid-cols-6"
        >
          <div class="space-y-1">
            <Label class="text-xs">{{ t('admin.storeSettings.code') }}</Label>
            <Input v-model="method.code" placeholder="standard" />
          </div>
          <div class="space-y-1 lg:col-span-2">
            <Label class="text-xs">{{ t('admin.storeSettings.label') }}</Label>
            <Input v-model="method.label" />
          </div>
          <div class="space-y-1">
            <Label class="text-xs">{{ t('admin.storeSettings.cents') }}</Label>
            <Input v-model="method.cents" type="number" min="0" />
          </div>
          <div class="space-y-1">
            <Label class="text-xs">{{ t('admin.storeSettings.minDays') }}</Label>
            <Input v-model="method.delivery_days_min" type="number" min="0" />
          </div>
          <div class="flex items-end gap-2">
            <div class="min-w-0 flex-1 space-y-1">
              <Label class="text-xs">{{ t('admin.storeSettings.maxDays') }}</Label>
              <Input v-model="method.delivery_days_max" type="number" min="0" />
            </div>
            <Button type="button" size="sm" variant="ghost" class="shrink-0 text-destructive" @click="removeShippingMethod(index)">{{ t('admin.ui.delete') }}</Button>
          </div>
        </div>
      </div>
      <p v-else class="text-sm text-muted-foreground">{{ t('admin.storeSettings.emptyShipping') }}</p>
    </section>

    <div v-for="setting in settings" :key="setting.key" class="rounded-lg border p-4 space-y-2">
      <Label :for="setting.key" class="text-sm font-medium">{{ setting.label }}</Label>
      <p v-if="setting.hint" class="text-xs text-muted-foreground">{{ setting.hint }}</p>
      <Input
        :id="setting.key"
        v-model="form.settings[setting.key]"
        :type="setting.input_type === 'number' ? 'number' : 'text'"
        :min="setting.input_type === 'number' ? 0 : undefined"
      />
    </div>
    <Button type="submit" :disabled="form.processing">{{ t('admin.storeSettings.save') }}</Button>
    <template v-if="testWebhookUrl">
      <Select v-model="selectedTestEvent" :options="testEventOptions" class="ml-2" size="sm" />
      <Button
        type="button"
        variant="outline"
        class="ml-2"
        @click="sendTestWebhook"
      >
        {{ t('admin.storeSettings.sendWebhookTest') }}
      </Button>
      <Button
        v-if="testAllWebhooksUrl"
        type="button"
        variant="outline"
        class="ml-2"
        @click="sendTestAllWebhooks"
      >
        {{ t('admin.storeSettings.batchWebhookTest') }}
      </Button>
      <p v-if="lastTestWebhookDisplay" class="mt-2 text-xs text-muted-foreground">
        {{ t('admin.storeSettings.lastTest', { event: lastTestWebhookDisplay.event_type, status: lastTestWebhookDisplay.status }) }}
        <span v-if="lastTestWebhookDisplay.response_code != null">{{ t('admin.storeSettings.lastTestHttp', { code: lastTestWebhookDisplay.response_code }) }}</span>
        · {{ lastTestWebhookDisplay.created_at }}
      </p>
    </template>
  </form>
</template>
