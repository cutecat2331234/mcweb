<script setup lang="ts">
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
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

const startsAt = computed<string | undefined>({
  get: () => form.coupon.starts_at || undefined,
  set: (value) => {
    form.coupon.starts_at = value || null
  },
})

const endsAt = computed<string | undefined>({
  get: () => form.coupon.ends_at || undefined,
  set: (value) => {
    form.coupon.ends_at = value || null
  },
})

function toggleProductId(id: number, checked: boolean) {
  const ids = form.coupon.product_ids || []
  form.coupon.product_ids = checked
    ? ids.includes(id) ? ids : [...ids, id]
    : ids.filter((currentId) => currentId !== id)
}

function toggleCategoryId(id: number, checked: boolean) {
  const ids = form.coupon.category_ids || []
  form.coupon.category_ids = checked
    ? ids.includes(id) ? ids : [...ids, id]
    : ids.filter((currentId) => currentId !== id)
}

function fieldError(field: string) {
  return form.errors[field] || form.errors[`coupon.${field}`]
}

function normalizeEmptyNumbers(record: object, fields: string[]) {
  const values = record as Record<string, unknown>
  fields.forEach((field) => {
    if (values[field] === undefined) values[field] = null
  })
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  normalizeEmptyNumbers(form.coupon, [
    'discount_value',
    'min_amount_cents',
    'usage_limit',
    'per_user_limit',
    'max_discount_cents',
  ])
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <section class="admin-store-coupon-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-form
      :model="form.coupon"
      layout="vertical"
      class="max-w-4xl"
      @submit="submit"
    >
      <a-space direction="vertical" fill :size="16">
        <a-card :bordered="true">
          <a-form-item
            field="code"
            :label="t('admin.forms.coupon.code')"
            :rules="[{ required: true, message: t('admin.forms.coupon.code') }]"
            :validate-status="fieldError('code') ? 'error' : undefined"
            :help="fieldError('code')"
          >
            <a-input v-model="form.coupon.code" allow-clear />
          </a-form-item>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="discount_type"
                :label="t('admin.forms.coupon.discountType')"
                :validate-status="fieldError('discount_type') ? 'error' : undefined"
                :help="fieldError('discount_type')"
              >
                <a-select
                  v-model="form.coupon.discount_type"
                  :options="discountTypeOptions"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="discount_value"
                :label="t('admin.forms.coupon.discountValue')"
                :rules="[{ required: true, message: t('admin.forms.coupon.discountValue') }]"
                :validate-status="fieldError('discount_value') ? 'error' : undefined"
                :help="fieldError('discount_value')"
              >
                <a-input-number
                  v-model="form.coupon.discount_value"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-form-item
            field="description"
            :label="t('admin.forms.coupon.publicDescription')"
            :validate-status="fieldError('description') ? 'error' : undefined"
            :help="fieldError('description')"
          >
            <a-input v-model="form.coupon.description" allow-clear />
          </a-form-item>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="min_amount_cents"
                :label="t('admin.forms.coupon.minAmount')"
                :validate-status="fieldError('min_amount_cents') ? 'error' : undefined"
                :help="fieldError('min_amount_cents')"
              >
                <a-input-number
                  v-model="form.coupon.min_amount_cents"
                  :min="0"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="max_discount_cents"
                :label="t('admin.forms.coupon.maxDiscount')"
                :validate-status="fieldError('max_discount_cents') ? 'error' : undefined"
                :help="fieldError('max_discount_cents')"
              >
                <a-input-number
                  v-model="form.coupon.max_discount_cents"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="usage_limit"
                :label="t('admin.forms.coupon.usageLimit')"
                :validate-status="fieldError('usage_limit') ? 'error' : undefined"
                :help="fieldError('usage_limit')"
              >
                <a-input-number
                  v-model="form.coupon.usage_limit"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="per_user_limit"
                :label="t('admin.forms.coupon.perUserLimit')"
                :validate-status="fieldError('per_user_limit') ? 'error' : undefined"
                :help="fieldError('per_user_limit')"
              >
                <a-input-number
                  v-model="form.coupon.per_user_limit"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="starts_at"
                :label="t('admin.forms.coupon.startsAt')"
                :validate-status="fieldError('starts_at') ? 'error' : undefined"
                :help="fieldError('starts_at')"
              >
                <a-date-picker
                  v-model="startsAt"
                  class="w-full"
                  show-time
                  format="YYYY-MM-DD HH:mm"
                  value-format="YYYY-MM-DDTHH:mm"
                  allow-clear
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="ends_at"
                :label="t('admin.forms.coupon.endsAt')"
                :validate-status="fieldError('ends_at') ? 'error' : undefined"
                :help="fieldError('ends_at')"
              >
                <a-date-picker
                  v-model="endsAt"
                  class="w-full"
                  show-time
                  format="YYYY-MM-DD HH:mm"
                  value-format="YYYY-MM-DDTHH:mm"
                  allow-clear
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-space direction="vertical" :size="12">
            <a-space>
              <a-switch v-model="form.coupon.first_order_only" />
              <a-typography-text>
                {{ t('admin.forms.coupon.firstOrderOnly') }}
              </a-typography-text>
            </a-space>
            <a-space v-if="storeFeatures.shipping">
              <a-switch v-model="form.coupon.free_shipping" />
              <a-typography-text>
                {{ t('admin.forms.coupon.freeShipping') }}
              </a-typography-text>
            </a-space>
            <a-space>
              <a-switch v-model="form.coupon.active" />
              <a-typography-text>{{ t('admin.common.enable') }}</a-typography-text>
            </a-space>
          </a-space>
        </a-card>

        <a-grid :cols="{ xs: 1, md: 2 }" :col-gap="16" :row-gap="16">
          <a-grid-item>
            <a-card :title="t('admin.forms.coupon.limitProducts')" :bordered="true">
              <a-scrollbar class="max-h-56 overflow-auto">
                <a-space direction="vertical" fill>
                  <a-checkbox
                    v-for="product in products || []"
                    :key="product.id"
                    :model-value="(form.coupon.product_ids || []).includes(product.id)"
                    @update:model-value="(checked: boolean) => toggleProductId(product.id, checked)"
                  >
                    {{ product.name }}
                  </a-checkbox>
                </a-space>
              </a-scrollbar>
              <a-empty
                v-if="!(products || []).length"
                :description="t('admin.forms.coupon.limitProducts')"
              />
            </a-card>
          </a-grid-item>

          <a-grid-item>
            <a-card :title="t('admin.forms.coupon.limitCategories')" :bordered="true">
              <a-scrollbar class="max-h-56 overflow-auto">
                <a-space direction="vertical" fill>
                  <a-checkbox
                    v-for="category in categories || []"
                    :key="category.id"
                    :model-value="(form.coupon.category_ids || []).includes(category.id)"
                    @update:model-value="(checked: boolean) => toggleCategoryId(category.id, checked)"
                  >
                    {{ category.name }}
                  </a-checkbox>
                </a-space>
              </a-scrollbar>
              <a-empty
                v-if="!(categories || []).length"
                :description="t('admin.forms.coupon.limitCategories')"
              />
            </a-card>
          </a-grid-item>
        </a-grid>

        <a-space wrap>
          <a-button type="primary" html-type="submit" :loading="form.processing">
            {{ t('admin.ui.save') }}
          </a-button>
          <Link
            :href="backUrl"
            class="arco-btn arco-btn-outline arco-btn-size-medium no-underline"
          >
            {{ t('admin.ui.cancel') }}
          </Link>
        </a-space>
      </a-space>
    </a-form>
  </section>
</template>
