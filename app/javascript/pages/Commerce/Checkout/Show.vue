<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface CheckoutItem {
  product_name: string
  variant_name?: string | null
  quantity: number
  total_label: string
}

export interface ProviderOption {
  value: string
  label: string
}

const props = defineProps<{
  items: CheckoutItem[]
  subtotalCents: number
  subtotalLabel: string
  providers: ProviderOption[]
  defaultProvider?: string
  pendingCouponCode?: string | null
  pendingGiftCardCode?: string | null
  previewCouponUrl: string
  previewGiftCardUrl: string
}>()

const form = useForm({
  checkout: {
    provider: props.defaultProvider || props.providers[0]?.value || 'fake',
    coupon_code: props.pendingCouponCode || '',
    gift_card_code: props.pendingGiftCardCode || '',
    notes: '',
  },
})

const couponMessage = ref<string | null>(null)
const couponError = ref<string | null>(null)
const giftCardMessage = ref<string | null>(null)
const giftCardError = ref<string | null>(null)
const discountLabel = ref<string | null>(null)
const giftCardLabel = ref<string | null>(null)
const totalLabel = ref<string | null>(props.subtotalLabel)
const previewing = ref(false)
const previewingGiftCard = ref(false)

async function previewGiftCard() {
  giftCardMessage.value = null
  giftCardError.value = null
  giftCardLabel.value = null
  if (!totalLabel.value) totalLabel.value = props.subtotalLabel

  if (!form.checkout.gift_card_code.trim()) return

  previewingGiftCard.value = true
  try {
    const response = await fetch(props.previewGiftCardUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
      },
      body: JSON.stringify({
        code: form.checkout.gift_card_code,
        coupon_code: form.checkout.coupon_code,
      }),
    })
    const data = await response.json()
    if (response.ok) {
      giftCardMessage.value = `礼品卡 ${data.code} 已应用`
      giftCardLabel.value = data.gift_card_amount_label
      totalLabel.value = data.total_label
    } else {
      giftCardError.value = data.error || '礼品卡无效'
    }
  } catch {
    giftCardError.value = '无法验证礼品卡'
  } finally {
    previewingGiftCard.value = false
  }
}

async function previewCoupon() {
  couponMessage.value = null
  couponError.value = null
  discountLabel.value = null
  totalLabel.value = props.subtotalLabel

  if (!form.checkout.coupon_code.trim()) return

  previewing.value = true
  try {
    const response = await fetch(props.previewCouponUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || '',
      },
      body: JSON.stringify({ code: form.checkout.coupon_code }),
    })
    const data = await response.json()
    if (response.ok) {
      couponMessage.value = `优惠码 ${data.code} 已应用`
      discountLabel.value = data.discount_label
      totalLabel.value = data.total_label
      if (form.checkout.gift_card_code.trim()) {
        await previewGiftCard()
      }
    } else {
      couponError.value = data.error || '优惠码无效'
    }
  } catch {
    couponError.value = '无法验证优惠码'
  } finally {
    previewing.value = false
  }
}

onMounted(() => {
  if (props.pendingCouponCode) {
    previewCoupon()
  } else if (props.pendingGiftCardCode) {
    previewGiftCard()
  }
})
</script>

<template>
  <PageHeader title="结账" />

  <div v-if="items.length" class="max-w-2xl space-y-6">
    <div class="rounded-lg border">
      <Table>
        <TableHeader><TableRow><TableHead>商品</TableHead><TableHead>数量</TableHead><TableHead>小计</TableHead></TableRow></TableHeader>
        <TableBody>
          <TableRow v-for="(item, index) in items" :key="index">
            <TableCell>
              {{ item.product_name }}
              <span v-if="item.variant_name" class="ml-1 text-xs text-muted-foreground">({{ item.variant_name }})</span>
            </TableCell>
            <TableCell>{{ item.quantity }}</TableCell>
            <TableCell>{{ item.total_label }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <div class="space-y-1 text-sm">
      <p>小计：{{ subtotalLabel }}</p>
      <p v-if="discountLabel" class="text-green-600">优惠：-{{ discountLabel }}</p>
      <p v-if="giftCardLabel" class="text-green-600">礼品卡：-{{ giftCardLabel }}</p>
      <p class="font-medium">应付：{{ totalLabel }}</p>
    </div>

    <form class="space-y-4" @submit.prevent="form.post(routes.storeCheckout)">
      <div class="space-y-2">
        <Label for="coupon">优惠码</Label>
        <div class="flex gap-2">
          <Input id="coupon" v-model="form.checkout.coupon_code" placeholder="输入优惠码" class="flex-1" />
          <Button type="button" variant="outline" :disabled="previewing" @click="previewCoupon">验证</Button>
        </div>
        <p v-if="couponMessage" class="text-sm text-green-600">{{ couponMessage }}</p>
        <p v-if="couponError" class="text-sm text-destructive">{{ couponError }}</p>
      </div>

      <div class="space-y-2">
        <Label for="gift_card">礼品卡</Label>
        <div class="flex gap-2">
          <Input id="gift_card" v-model="form.checkout.gift_card_code" placeholder="输入礼品卡代码" class="flex-1" />
          <Button type="button" variant="outline" :disabled="previewingGiftCard" @click="previewGiftCard">验证</Button>
        </div>
        <p v-if="giftCardMessage" class="text-sm text-green-600">{{ giftCardMessage }}</p>
        <p v-if="giftCardError" class="text-sm text-destructive">{{ giftCardError }}</p>
      </div>

      <div class="space-y-2">
        <Label for="notes">订单备注（可选）</Label>
        <Textarea id="notes" v-model="form.checkout.notes" rows="2" placeholder="如有特殊说明请填写…" />
      </div>

      <div class="space-y-2">
        <Label for="provider">支付方式</Label>
        <select id="provider" v-model="form.checkout.provider" class="flex h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm">
          <option v-for="provider in providers" :key="provider.value" :value="provider.value">{{ provider.label }}</option>
        </select>
      </div>
      <Button type="submit" :disabled="form.processing">立即支付</Button>
    </form>
  </div>

  <div v-else class="space-y-4">
    <p class="text-sm text-muted-foreground">购物车是空的。</p>
    <Button as-child variant="outline">
      <Link :href="routes.storeCart">查看购物车</Link>
    </Button>
  </div>
</template>
