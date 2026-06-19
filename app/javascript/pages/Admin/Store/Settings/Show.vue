<script setup lang="ts">
import { useForm, router } from '@inertiajs/vue3'
import { ref, onBeforeUnmount, computed } from 'vue'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import { confirm } from '@/lib/useConfirm'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

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
    label: '新配送方式',
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
    title: '发送 Webhook 测试',
    message: `向配置的 Webhook URL 发送 ${selectedTestEvent.value} 测试事件？`,
  })
  if (!props.testWebhookUrl || !ok) return
  router.post(props.testWebhookUrl, { event: selectedTestEvent.value }, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}

async function sendTestAllWebhooks() {
  const ok = await confirm({
    title: '批量发送 Webhook 测试',
    message: '向配置的 Webhook URL 批量发送全部订单 Webhook 测试事件？',
  })
  if (!props.testAllWebhooksUrl || !ok) return
  router.post(props.testAllWebhooksUrl, {}, {
    onSuccess: () => startPollingWebhookStatus(),
  })
}
</script>

<template>
  <PageHeader title="商城设置" subtitle="运费、购物车、对比、SEO 与订单策略（对标 XenForo 资源管理 / WooCommerce 商店选项）" />

  <form class="max-w-3xl space-y-6" @submit.prevent="submit">
    <section class="space-y-4 rounded-lg border p-4">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h2 class="text-sm font-semibold">配送方式</h2>
          <p class="text-xs text-muted-foreground">可视化编辑结账可选配送方式；标准配送（code=standard）运费会同步「固定运费」设置。</p>
        </div>
        <Button type="button" size="sm" variant="outline" @click="addShippingMethod">添加配送方式</Button>
      </div>

      <div v-if="shippingMethods.length" class="space-y-3">
        <div
          v-for="(method, index) in shippingMethods"
          :key="`${method.code}-${index}`"
          class="grid gap-2 rounded-md border p-3 sm:grid-cols-2 lg:grid-cols-6"
        >
          <div class="space-y-1">
            <Label class="text-xs">代码</Label>
            <Input v-model="method.code" placeholder="standard" />
          </div>
          <div class="space-y-1 lg:col-span-2">
            <Label class="text-xs">名称</Label>
            <Input v-model="method.label" placeholder="标准配送" />
          </div>
          <div class="space-y-1">
            <Label class="text-xs">运费（分）</Label>
            <Input v-model="method.cents" type="number" min="0" />
          </div>
          <div class="space-y-1">
            <Label class="text-xs">最短天数</Label>
            <Input v-model="method.delivery_days_min" type="number" min="0" />
          </div>
          <div class="flex items-end gap-2">
            <div class="min-w-0 flex-1 space-y-1">
              <Label class="text-xs">最长天数</Label>
              <Input v-model="method.delivery_days_max" type="number" min="0" />
            </div>
            <Button type="button" size="sm" variant="ghost" class="shrink-0 text-destructive" @click="removeShippingMethod(index)">删除</Button>
          </div>
        </div>
      </div>
      <p v-else class="text-sm text-muted-foreground">暂无配送方式，请添加至少一种。</p>
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
    <Button type="submit" :disabled="form.processing">保存商城设置</Button>
    <template v-if="testWebhookUrl">
      <Select v-model="selectedTestEvent" :options="testEventOptions" class="ml-2" size="sm" />
      <Button
        type="button"
        variant="outline"
        class="ml-2"
        @click="sendTestWebhook"
      >
        发送 Webhook 测试
      </Button>
      <Button
        v-if="testAllWebhooksUrl"
        type="button"
        variant="outline"
        class="ml-2"
        @click="sendTestAllWebhooks"
      >
        批量测试全部事件
      </Button>
      <p v-if="lastTestWebhookDisplay" class="mt-2 text-xs text-muted-foreground">
        最近测试：{{ lastTestWebhookDisplay.event_type }} · {{ lastTestWebhookDisplay.status }}
        <span v-if="lastTestWebhookDisplay.response_code != null"> · HTTP {{ lastTestWebhookDisplay.response_code }}</span>
        · {{ lastTestWebhookDisplay.created_at }}
      </p>
    </template>
  </form>
</template>
