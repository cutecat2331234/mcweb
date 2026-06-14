<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  gift_card: {
    code: string
    balance_cents: number
    currency: string
    expires_at: string | null
    note: string
    active: boolean
  }
  submitUrl: string
  backUrl: string
}>()

const form = useForm({ gift_card: { ...props.gift_card } })

function submit() {
  form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="code">礼品卡代码</Label>
      <Input id="code" v-model="form.gift_card.code" placeholder="留空自动生成" />
      <p class="text-xs text-muted-foreground">留空将自动生成 GC 开头的代码。</p>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="balance_cents">面额（分）</Label>
        <Input id="balance_cents" v-model.number="form.gift_card.balance_cents" type="number" min="1" required />
      </div>
      <div class="space-y-2">
        <Label for="currency">货币</Label>
        <Input id="currency" v-model="form.gift_card.currency" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="expires_at">过期时间（可选）</Label>
      <Input id="expires_at" v-model="form.gift_card.expires_at" type="datetime-local" />
    </div>
    <div class="space-y-2">
      <Label for="note">备注</Label>
      <Input id="note" v-model="form.gift_card.note" placeholder="内部备注" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <input v-model="form.gift_card.active" type="checkbox" class="h-4 w-4" />
      启用
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">创建</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
