<script setup lang="ts">
import { Link, router, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

defineOptions({ layout: AdminLayout })

export interface DetailField {
  label: string
  value: string
}

export interface DetailSection {
  title: string
  items: Array<{ label: string; value?: string }>
}

export interface DetailAction {
  label: string
  href: string
  method?: 'get' | 'post' | 'patch' | 'delete'
  confirm?: string
  variant?: 'default' | 'outline'
  data?: Record<string, unknown>
}

export interface MuteForm {
  user_id: string
  action_url: string
}

export interface RefundForm {
  action_url: string
  max_cents: number
  max_label: string
}

export interface BanForm {
  banned: boolean
  ban_url: string
  unban_url: string
}

const props = defineProps<{
  title: string
  subtitle?: string
  fields: DetailField[]
  sections?: DetailSection[]
  preformatted?: { title: string; content: string }
  actions?: DetailAction[]
  muteForm?: MuteForm | null
  banForm?: BanForm | null
  refundForm?: RefundForm | null
  backUrl: string
}>()

const muteForm = useForm({
  user_id: props.muteForm?.user_id || '',
  reason: '',
  expires_at: '',
})

const banForm = useForm({
  reason: '',
  expires_at: '',
})

const refundForm = useForm({
  amount_cents: props.refundForm?.max_cents || 0,
  reason: '',
})

function submitMute() {
  if (!props.muteForm) return
  muteForm.post(props.muteForm.action_url)
}

function submitBan() {
  if (!props.banForm || props.banForm.banned) return
  banForm.post(props.banForm.ban_url)
}

function submitUnban() {
  if (!props.banForm || !props.banForm.banned) return
  router.post(props.banForm.unban_url)
}

function submitRefund() {
  if (!props.refundForm) return
  router.patch(props.refundForm.action_url, {
    refund: true,
    amount_cents: refundForm.amount_cents,
    reason: refundForm.reason,
  })
}
</script>

<template>
  <PageHeader :title="title" :subtitle="subtitle" />

  <Card class="max-w-3xl">
    <CardContent class="space-y-3 pt-6">
      <div v-for="field in fields" :key="field.label" class="flex justify-between gap-4 text-sm">
        <span class="text-muted-foreground">{{ field.label }}</span>
        <span class="text-right font-medium">{{ field.value }}</span>
      </div>
    </CardContent>
  </Card>

  <div v-for="section in sections" :key="section.title" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ section.title }}</h2>
    <ul class="space-y-2 rounded-lg border p-4 text-sm">
      <li v-for="(item, index) in section.items" :key="index">
        <code v-if="item.label" class="text-xs text-muted-foreground">{{ item.label }}</code>
        <span v-if="item.value"> — {{ item.value }}</span>
      </li>
    </ul>
  </div>

  <div v-if="preformatted" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ preformatted.title }}</h2>
    <pre class="overflow-auto rounded-lg border bg-muted p-4 text-xs">{{ preformatted.content }}</pre>
  </div>

  <form v-if="props.muteForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitMute">
    <h2 class="text-sm font-semibold">禁言用户</h2>
    <div class="space-y-2">
      <Label>原因</Label>
      <Input v-model="muteForm.reason" placeholder="禁言原因" />
    </div>
    <div class="space-y-2">
      <Label>到期时间（空=永久）</Label>
      <Input v-model="muteForm.expires_at" type="datetime-local" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="muteForm.processing">禁言</Button>
  </form>

  <form v-if="props.banForm && !props.banForm.banned" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitBan">
    <h2 class="text-sm font-semibold">封禁用户</h2>
    <div class="space-y-2">
      <Label>封禁原因</Label>
      <Input v-model="banForm.reason" placeholder="封禁原因" />
    </div>
    <div class="space-y-2">
      <Label>到期时间（空=永久）</Label>
      <Input v-model="banForm.expires_at" type="datetime-local" />
    </div>
    <Button type="submit" variant="destructive" size="sm" :disabled="banForm.processing">封禁账号</Button>
  </form>

  <div v-if="props.banForm?.banned" class="mt-6 max-w-lg rounded-lg border p-4">
    <p class="mb-3 text-sm text-destructive">该用户当前处于封禁状态。</p>
    <Button type="button" size="sm" variant="outline" @click="submitUnban">解除封禁</Button>
  </div>

  <form v-if="props.refundForm" class="mt-6 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="submitRefund">
    <h2 class="text-sm font-semibold">部分退款</h2>
    <p class="text-xs text-muted-foreground">最多可退 {{ props.refundForm.max_label }}</p>
    <div class="space-y-2">
      <Label>退款金额（分）</Label>
      <Input v-model.number="refundForm.amount_cents" type="number" :max="props.refundForm.max_cents" min="1" required />
    </div>
    <div class="space-y-2">
      <Label>原因</Label>
      <Input v-model="refundForm.reason" placeholder="退款原因" />
    </div>
    <Button type="submit" size="sm" :disabled="refundForm.processing">处理退款</Button>
  </form>

  <div class="mt-6 flex flex-wrap gap-3">
    <template v-for="action in actions" :key="action.href + action.label">
      <Button
        v-if="action.method && action.method !== 'get'"
        as-child
        :variant="action.variant ?? 'default'"
      >
        <Link
          :href="action.href"
          :method="action.method"
          as="button"
          :data="action.data"
        >
          {{ action.label }}
        </Link>
      </Button>
      <Button v-else as-child :variant="action.variant ?? 'outline'">
        <Link :href="action.href">{{ action.label }}</Link>
      </Button>
    </template>
    <Button as-child variant="outline">
      <Link :href="backUrl">返回</Link>
    </Button>
  </div>
</template>
