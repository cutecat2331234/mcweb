<script setup lang="ts">
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { resolveStoreFeatures } from '@/lib/storeFeatures'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()
const page = usePage()
const storeFeatures = computed(() =>
  resolveStoreFeatures(page.props.storeFeatures as Parameters<typeof resolveStoreFeatures>[0]),
)

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
    ends_at?: string | null
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

const discountTypeOptions = computed(() => [
  { value: 'percentage', label: t('admin.forms.coupon.typePercentage') },
  { value: 'fixed', label: t('admin.forms.coupon.typeFixed') },
])

function toggleProductId(id: number, checked: boolean) {
  const ids = form.coupon.product_ids || []
  form.coupon.product_ids = checked
    ? ids.includes(id) ? ids : [...ids, id]
    : ids.filter((x) => x !== id)
}

function toggleCategoryId(id: number, checked: boolean) {
  const ids = form.coupon.category_ids || []
  form.coupon.category_ids = checked
    ? ids.includes(id) ? ids : [...ids, id]
    : ids.filter((x) => x !== id)
}

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
      <Label for="code">{{ t('admin.forms.coupon.code') }}</Label>
      <Input id="code" v-model="form.coupon.code" required />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="discount_type">{{ t('admin.forms.coupon.discountType') }}</Label>
        <Select id="discount_type" v-model="form.coupon.discount_type" :options="discountTypeOptions" block />
      </div>
      <div class="space-y-2">
        <Label for="discount_value">{{ t('admin.forms.coupon.discountValue') }}</Label>
        <Input id="discount_value" v-model.number="form.coupon.discount_value" type="number" min="1" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="min_amount_cents">{{ t('admin.forms.coupon.minAmount') }}</Label>
      <Input id="min_amount_cents" v-model.number="form.coupon.min_amount_cents" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.forms.coupon.publicDescription') }}</Label>
      <Input id="description" v-model="form.coupon.description" />
    </div>
    <div class="space-y-2">
      <Label for="usage_limit">{{ t('admin.forms.coupon.usageLimit') }}</Label>
      <Input id="usage_limit" v-model.number="form.coupon.usage_limit" type="number" min="1" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="starts_at">{{ t('admin.forms.coupon.startsAt') }}</Label>
        <Input id="starts_at" v-model="form.coupon.starts_at" type="datetime-local" />
      </div>
      <div class="space-y-2">
        <Label for="ends_at">{{ t('admin.forms.coupon.endsAt') }}</Label>
        <Input id="ends_at" v-model="form.coupon.ends_at" type="datetime-local" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="per_user_limit">{{ t('admin.forms.coupon.perUserLimit') }}</Label>
      <Input id="per_user_limit" v-model.number="form.coupon.per_user_limit" type="number" min="1" />
    </div>
    <div class="space-y-2">
      <Label for="max_discount_cents">{{ t('admin.forms.coupon.maxDiscount') }}</Label>
      <Input id="max_discount_cents" v-model.number="form.coupon.max_discount_cents" type="number" min="1" />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.coupon.first_order_only" />
      {{ t('admin.forms.coupon.firstOrderOnly') }}
    </label>
    <label v-if="storeFeatures.shipping" class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.coupon.free_shipping" />
      {{ t('admin.forms.coupon.freeShipping') }}
    </label>
    <div class="space-y-2">
      <Label>{{ t('admin.forms.coupon.limitProducts') }}</Label>
      <div class="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2 text-sm">
        <label v-for="product in products || []" :key="product.id" class="flex items-center gap-2">
          <Checkbox
            :model-value="(form.coupon.product_ids || []).includes(product.id)"
            @update:model-value="(checked) => toggleProductId(product.id, checked)"
          />
          {{ product.name }}
        </label>
      </div>
    </div>
    <div class="space-y-2">
      <Label>{{ t('admin.forms.coupon.limitCategories') }}</Label>
      <div class="max-h-40 space-y-1 overflow-y-auto rounded-md border p-2 text-sm">
        <label v-for="category in categories || []" :key="category.id" class="flex items-center gap-2">
          <Checkbox
            :model-value="(form.coupon.category_ids || []).includes(category.id)"
            @update:model-value="(checked) => toggleCategoryId(category.id, checked)"
          />
          {{ category.name }}
        </label>
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.coupon.active" />
      {{ t('admin.common.enable') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
