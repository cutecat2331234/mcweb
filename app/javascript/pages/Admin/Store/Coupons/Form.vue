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
  coupon: {
    id?: number
    code: string
    discount_type: string
    discount_value: number
    min_amount_cents: number
    usage_limit: number | null
    per_user_limit?: number | null
    first_order_only?: boolean
    max_discount_cents?: number | null
    active: boolean
    starts_at: string | null
    product_ids?: number[]
    category_ids?: number[]
    description?: string
    free_shipping?: boolean
  }
  products?: Array<{ id: number; name: string }>
  categories?: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ coupon: { ...props.coupon } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="code">优惠码</Label>
      <Input id="code" v-model="form.coupon.code" required />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="discount_type">类型</Label>
        <select id="discount_type" v-model="form.coupon.discount_type" class="h-9 w-full rounded-md border px-2 text-sm">
          <option value="percentage">百分比</option>
          <option value="fixed">固定金额（分）</option>
        </select>
      </div>
      <div class="space-y-2">
        <Label for="discount_value">折扣值</Label>
        <Input id="discount_value" v-model.number="form.coupon.discount_value" type="number" min="1" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="min_amount_cents">最低消费（分）</Label>
      <Input id="min_amount_cents" v-model.number="form.coupon.min_amount_cents" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="description">公开说明（优惠券详情页展示）</Label>
      <Input id="description" v-model="form.coupon.description" />
    </div>
    <div class="space-y-2">
      <Label for="usage_limit">使用上限（空=无限）</Label>
      <Input id="usage_limit" v-model.number="form.coupon.usage_limit" type="number" min="1" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="starts_at">开始时间</Label>
        <Input id="starts_at" v-model="form.coupon.starts_at" type="datetime-local" />
      </div>
      <div class="space-y-2">
        <Label for="ends_at">结束时间</Label>
        <Input id="ends_at" v-model="form.coupon.ends_at" type="datetime-local" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="per_user_limit">每用户使用上限（空=无限）</Label>
      <Input id="per_user_limit" v-model.number="form.coupon.per_user_limit" type="number" min="1" />
    </div>
    <div class="space-y-2">
      <Label for="max_discount_cents">最大折扣金额（分，空=不限）</Label>
      <Input id="max_discount_cents" v-model.number="form.coupon.max_discount_cents" type="number" min="1" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <input v-model="form.coupon.first_order_only" type="checkbox" class="h-4 w-4" />
      仅限首单
    </label>
    <label class="flex items-center gap-2 text-sm">
      <input v-model="form.coupon.free_shipping" type="checkbox" class="h-4 w-4" />
      免运费
    </label>
    <div class="space-y-2">
      <Label>限定商品（不选=全部）</Label>
      <div class="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2 text-sm">
        <label v-for="product in products || []" :key="product.id" class="flex items-center gap-2">
          <input v-model="form.coupon.product_ids" type="checkbox" :value="product.id" class="h-4 w-4" />
          {{ product.name }}
        </label>
      </div>
    </div>
    <div class="space-y-2">
      <Label>限定分类（不选=全部）</Label>
      <div class="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2 text-sm">
        <label v-for="category in categories || []" :key="category.id" class="flex items-center gap-2">
          <input v-model="form.coupon.category_ids" type="checkbox" :value="category.id" class="h-4 w-4" />
          {{ category.name }}
        </label>
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <input v-model="form.coupon.active" type="checkbox" class="h-4 w-4" />
      启用
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
