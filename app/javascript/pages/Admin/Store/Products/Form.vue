<script setup lang="ts">
import { Link, useForm, usePage } from '@inertiajs/vue3'
import { computed, onMounted, ref } from 'vue'
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
  product: {
    public_id?: string
    name: string
    slug: string
    description: string
    summary?: string
    product_type: string
    status: string
    price_cents: number
    compare_at_price_cents?: number | null
    currency: string
    stock: number | null
    store_category_id: number | null
    store_membership_type_id?: number | null
    prerequisite_match_mode?: string
    purchase_limit: number | null
    allow_backorder?: boolean
    minimum_quantity?: number
    maximum_quantity?: number | null
    requires_shipping?: boolean
    image_url: string
    gallery_urls: string
    fulfillment_config: string
    featured?: boolean
    version?: string
    changelog?: string
    seo_title?: string
    seo_description?: string
    available_at?: string
    unavailable_at?: string
    variants: Array<{ id?: number; name: string; sku: string; price_cents: number; stock: number | null }>
    prerequisites?: Array<{ id?: number; required_product_id: number | null; requirement_mode: string; _destroy?: boolean }>
  }
  categories: Array<{ id: number; name: string }>
  membership_types?: Array<{ id: number; name: string }>
  prerequisite_products?: Array<{ id: number; name: string }>
  fulfillment_providers?: Array<{
    id: string
    key: string
    plugin_id: string
    plugin_name: string
    plugin_version: string
  }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  uploadUrl?: string | null
}>()

const form = useForm({
  product: {
    ...props.product,
    variants: props.product.variants?.length ? [...props.product.variants] : [],
    prerequisites: props.product.prerequisites?.length ? [...props.product.prerequisites] : [],
  },
})

const productTypeOptions = computed(() => {
  const options = [
    { value: 'virtual', label: t('admin.forms.product.typeVirtual') },
    { value: 'physical', label: t('admin.forms.product.typePhysical') },
    { value: 'gift_card', label: t('admin.forms.product.typeGiftCard') },
    { value: 'digital', label: t('admin.forms.product.typeDigital') },
    { value: 'membership', label: t('admin.forms.product.typeMembership') },
  ]
  if (!storeFeatures.value.physical_products) {
    return options.filter((option) => option.value !== 'physical')
  }
  return options
})

const statusOptions = computed(() => [
  { value: 'draft', label: t('admin.forms.product.statusDraft') },
  { value: 'active', label: t('admin.forms.product.statusActive') },
  { value: 'archived', label: t('admin.forms.product.statusArchived') },
])

const categoryOptions = computed(() => [
  { value: '', label: t('admin.common.noCategory') },
  ...props.categories.map((cat) => ({ value: String(cat.id), label: cat.name })),
])

const membershipTypeOptions = computed(() => [
  { value: '', label: t('admin.forms.product.selectMembershipType') },
  ...(props.membership_types || []).map((type) => ({ value: String(type.id), label: type.name })),
])

const prerequisiteMatchOptions = computed(() => [
  { value: 'all', label: t('admin.forms.product.prerequisiteMatchAll') },
  { value: 'any', label: t('admin.forms.product.prerequisiteMatchAny') },
])

const requirementModeOptions = computed(() => [
  { value: 'ever_purchased', label: t('admin.forms.product.prerequisiteEverPurchased') },
  { value: 'active', label: t('admin.forms.product.prerequisiteActive') },
])

const prerequisiteProductOptions = computed(() =>
  (props.prerequisite_products || []).map((p) => ({ value: String(p.id), label: p.name })),
)

type ImagePackInfo = { label?: string; namespace?: string; available?: boolean }

const imagePacks = computed(
  () => (page.props.imagePacks as Record<string, ImagePackInfo> | undefined) || {},
)

const imagePackOptions = computed(() => [
  { value: '', label: t('admin.forms.product.imagePackNone') },
  ...Object.entries(imagePacks.value)
    .filter(([, pack]) => pack?.available)
    .map(([id, pack]) => ({ value: id, label: pack.label || id })),
])

const imagePackId = ref('')
const imageTexture = ref('')
const fulfillmentProviderId = ref('')

const fulfillmentProviderOptions = computed(() => {
  const options = [
    {
      value: '',
      label: t('admin.forms.product.fulfillmentProviderBuiltIn'),
    },
    ...(props.fulfillment_providers || []).map((provider) => ({
      value: provider.id,
      label: `${provider.plugin_name} · ${provider.key} (${provider.plugin_version})`,
    })),
  ]
  if (
    fulfillmentProviderId.value &&
    !options.some((option) => option.value === fulfillmentProviderId.value)
  ) {
    options.push({
      value: fulfillmentProviderId.value,
      label: t('admin.forms.product.fulfillmentProviderUnavailable', {
        id: fulfillmentProviderId.value,
      }),
    })
  }
  return options
})

const availableAt = computed<string | undefined>({
  get: () => form.product.available_at || undefined,
  set: (value) => {
    form.product.available_at = value || ''
  },
})

const unavailableAt = computed<string | undefined>({
  get: () => form.product.unavailable_at || undefined,
  set: (value) => {
    form.product.unavailable_at = value || ''
  },
})

const imagePackPreviewUrl = computed(() => {
  if (!imagePackId.value || !imageTexture.value.trim()) return null
  const segments = imageTexture.value.trim().split('/').filter(Boolean)
  if (!segments.length) return null
  return `/app/store/image-packs/${encodeURIComponent(imagePackId.value)}/${segments.map(encodeURIComponent).join('/')}`
})

function parseFulfillmentConfig(): Record<string, unknown> {
  try {
    return JSON.parse(form.product.fulfillment_config || '{}') as Record<string, unknown>
  } catch {
    return {}
  }
}

function syncImagePackToFulfillmentConfig() {
  const config = parseFulfillmentConfig()
  if (imagePackId.value) {
    config.image_pack = imagePackId.value
  } else {
    delete config.image_pack
    delete config.image_texture
  }
  if (imagePackId.value && imageTexture.value.trim()) {
    config.image_texture = imageTexture.value.trim()
  } else {
    delete config.image_texture
  }
  form.product.fulfillment_config = JSON.stringify(config, null, 2)
}

function loadImagePackFromFulfillmentConfig() {
  const config = parseFulfillmentConfig()
  imagePackId.value = String(config.image_pack || config.image_pack_id || '')
  imageTexture.value = String(config.image_texture || config.image_pack_texture || '')
}

function updateMembershipTypeId(value: string) {
  form.product.store_membership_type_id = value ? Number(value) : null
}

function addPrerequisite() {
  form.product.prerequisites.push({ required_product_id: null, requirement_mode: 'ever_purchased' })
}

function removePrerequisite(prerequisite: (typeof form.product.prerequisites)[number]) {
  const index = form.product.prerequisites.indexOf(prerequisite)
  if (index < 0) return
  const item = form.product.prerequisites[index]
  if (item.id) {
    form.product.prerequisites[index] = { ...item, _destroy: true } as typeof item & { _destroy: boolean }
  } else {
    form.product.prerequisites.splice(index, 1)
  }
}

function updateCategoryId(value: string) {
  form.product.store_category_id = value ? Number(value) : null
}

function addVariant() {
  form.product.variants.push({ name: '', sku: '', price_cents: form.product.price_cents, stock: null })
}

function removeVariant(variant: (typeof form.product.variants)[number]) {
  const index = form.product.variants.indexOf(variant)
  if (index < 0) return
  const entry = form.product.variants[index]
  if (entry.id) {
    form.product.variants[index] = { ...entry, _destroy: true } as typeof entry & { _destroy: boolean }
  } else {
    form.product.variants.splice(index, 1)
  }
}

function syncFulfillmentProviderToConfig() {
  const config = parseFulfillmentConfig()
  delete config.fulfillment_provider
  if (fulfillmentProviderId.value) {
    config.plugin_provider = fulfillmentProviderId.value
  } else {
    delete config.plugin_provider
  }
  form.product.fulfillment_config = JSON.stringify(config, null, 2)
}

function loadFulfillmentProviderFromConfig() {
  const config = parseFulfillmentConfig()
  fulfillmentProviderId.value = String(
    config.plugin_provider || config.fulfillment_provider || '',
  )
}

function fieldError(field: string) {
  return form.errors[field] || form.errors[`product.${field}`]
}

function normalizeEmptyNumbers(record: object, fields: string[]) {
  const values = record as Record<string, unknown>
  fields.forEach((field) => {
    if (values[field] === undefined) values[field] = null
  })
}

function submit(event?: { errors?: unknown }) {
  if (event?.errors) return
  if (!storeFeatures.value.physical_products && form.product.product_type === 'physical') {
    form.product.product_type = 'virtual'
  }
  if (!storeFeatures.value.shipping) {
    form.product.requires_shipping = false
  }
  syncImagePackToFulfillmentConfig()
  syncFulfillmentProviderToConfig()
  form.product.prerequisites = form.product.prerequisites.filter(
    (p) => p._destroy || p.required_product_id,
  )
  normalizeEmptyNumbers(form.product, [
    'price_cents',
    'compare_at_price_cents',
    'stock',
    'purchase_limit',
    'minimum_quantity',
    'maximum_quantity',
  ])
  form.product.variants.forEach((variant) => {
    normalizeEmptyNumbers(variant, ['price_cents', 'stock'])
  })
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}

async function uploadCover(file: File) {
  if (!props.uploadUrl) return
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content
  const body = new FormData()
  body.append('file', file)
  const res = await fetch(props.uploadUrl, {
    method: 'POST',
    headers: { 'X-CSRF-Token': token || '' },
    body,
    credentials: 'same-origin',
  })
  const data = await res.json()
  if (res.ok && data.url) form.product.image_url = data.url
}

function beforeCoverUpload(file: File) {
  void uploadCover(file)
  return false
}

onMounted(() => {
  if (!storeFeatures.value.physical_products && form.product.product_type === 'physical') {
    form.product.product_type = 'virtual'
  }
  if (!storeFeatures.value.shipping) {
    form.product.requires_shipping = false
  }
  loadImagePackFromFulfillmentConfig()
  loadFulfillmentProviderFromConfig()
})
</script>

<template>
  <section class="admin-store-product-form">
    <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />

    <a-form
      :model="form.product"
      layout="vertical"
      class="max-w-5xl"
      @submit="submit"
    >
      <a-space direction="vertical" fill :size="16">
        <a-card :bordered="true">
          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="name"
                :label="t('admin.common.name')"
                :rules="[{ required: true, message: t('admin.common.name') }]"
                :validate-status="fieldError('name') ? 'error' : undefined"
                :help="fieldError('name')"
              >
                <a-input v-model="form.product.name" allow-clear />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="slug"
                :label="t('admin.common.slugFull')"
                :rules="[{ required: true, message: t('admin.common.slugFull') }]"
                :validate-status="fieldError('slug') ? 'error' : undefined"
                :help="fieldError('slug')"
              >
                <a-input v-model="form.product.slug" allow-clear />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-form-item
            field="summary"
            :label="t('admin.forms.product.summary')"
            :validate-status="fieldError('summary') ? 'error' : undefined"
            :help="fieldError('summary')"
          >
            <a-textarea
              v-model="form.product.summary"
              :auto-size="{ minRows: 2, maxRows: 5 }"
              :placeholder="t('admin.forms.product.summaryPlaceholder')"
              allow-clear
            />
          </a-form-item>

          <a-form-item
            field="description"
            :label="t('admin.common.description')"
            :validate-status="fieldError('description') ? 'error' : undefined"
            :help="fieldError('description')"
          >
            <a-textarea
              v-model="form.product.description"
              :auto-size="{ minRows: 4, maxRows: 12 }"
              allow-clear
            />
          </a-form-item>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="product_type"
                :label="t('admin.forms.product.type')"
                :validate-status="fieldError('product_type') ? 'error' : undefined"
                :help="fieldError('product_type')"
              >
                <a-select
                  v-model="form.product.product_type"
                  :options="productTypeOptions"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="status"
                :label="t('admin.common.status')"
                :validate-status="fieldError('status') ? 'error' : undefined"
                :help="fieldError('status')"
              >
                <a-select v-model="form.product.status" :options="statusOptions" />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="store_category_id"
                :label="t('admin.forms.product.category')"
                :validate-status="fieldError('store_category_id') ? 'error' : undefined"
                :help="fieldError('store_category_id')"
              >
                <a-select
                  :model-value="form.product.store_category_id == null ? '' : String(form.product.store_category_id)"
                  :options="categoryOptions"
                  allow-search
                  @update:model-value="updateCategoryId"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item v-if="form.product.product_type === 'membership'">
              <a-form-item
                field="store_membership_type_id"
                :label="t('admin.forms.product.membershipType')"
                :validate-status="fieldError('store_membership_type_id') ? 'error' : undefined"
                :help="fieldError('store_membership_type_id')"
              >
                <a-select
                  :model-value="form.product.store_membership_type_id == null ? '' : String(form.product.store_membership_type_id)"
                  :options="membershipTypeOptions"
                  allow-search
                  @update:model-value="updateMembershipTypeId"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>
        </a-card>

        <a-card :bordered="true">
          <a-grid :cols="{ xs: 1, sm: 2, lg: 3 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="price_cents"
                :label="t('admin.forms.product.priceCents')"
                :rules="[{ required: true, message: t('admin.forms.product.priceCents') }]"
                :validate-status="fieldError('price_cents') ? 'error' : undefined"
                :help="fieldError('price_cents')"
              >
                <a-input-number
                  v-model="form.product.price_cents"
                  :min="0"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="compare_at_price_cents"
                :label="t('admin.forms.product.comparePrice')"
                :validate-status="fieldError('compare_at_price_cents') ? 'error' : undefined"
                :help="fieldError('compare_at_price_cents')"
              >
                <a-input-number
                  v-model="form.product.compare_at_price_cents"
                  :min="0"
                  :placeholder="t('admin.forms.product.comparePlaceholder')"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="stock"
                :label="t('admin.forms.product.stock')"
                :validate-status="fieldError('stock') ? 'error' : undefined"
                :help="fieldError('stock')"
              >
                <a-input-number v-model="form.product.stock" :min="0" class="w-full" />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-grid :cols="{ xs: 1, sm: 3 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="purchase_limit"
                :label="t('admin.forms.product.purchaseLimit')"
                :validate-status="fieldError('purchase_limit') ? 'error' : undefined"
                :help="fieldError('purchase_limit')"
              >
                <a-input-number
                  v-model="form.product.purchase_limit"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="minimum_quantity"
                :label="t('admin.forms.product.minQty')"
                :validate-status="fieldError('minimum_quantity') ? 'error' : undefined"
                :help="fieldError('minimum_quantity')"
              >
                <a-input-number
                  v-model="form.product.minimum_quantity"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="maximum_quantity"
                :label="t('admin.forms.product.maxQty')"
                :validate-status="fieldError('maximum_quantity') ? 'error' : undefined"
                :help="fieldError('maximum_quantity')"
              >
                <a-input-number
                  v-model="form.product.maximum_quantity"
                  :min="1"
                  class="w-full"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="available_at"
                :label="t('admin.forms.product.availableAt')"
                :validate-status="fieldError('available_at') ? 'error' : undefined"
                :help="fieldError('available_at')"
              >
                <a-date-picker
                  v-model="availableAt"
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
                field="unavailable_at"
                :label="t('admin.forms.product.unavailableAt')"
                :validate-status="fieldError('unavailable_at') ? 'error' : undefined"
                :help="fieldError('unavailable_at')"
              >
                <a-date-picker
                  v-model="unavailableAt"
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
            <a-space v-if="storeFeatures.shipping">
              <a-switch v-model="form.product.requires_shipping" />
              <a-typography-text>
                {{ t('admin.forms.product.requiresShipping') }}
              </a-typography-text>
            </a-space>
            <a-space>
              <a-switch v-model="form.product.featured" />
              <a-typography-text>{{ t('admin.forms.product.featured') }}</a-typography-text>
            </a-space>
            <a-space>
              <a-switch v-model="form.product.allow_backorder" />
              <a-typography-text>
                {{ t('admin.forms.product.allowBackorder') }}
              </a-typography-text>
            </a-space>
          </a-space>
        </a-card>

        <a-card
          :title="t('admin.forms.product.prerequisites')"
          :bordered="true"
        >
          <template #extra>
            <a-button html-type="button" size="small" @click="addPrerequisite">
              {{ t('admin.forms.product.addPrerequisite') }}
            </a-button>
          </template>

          <a-form-item
            field="prerequisite_match_mode"
            :label="t('admin.forms.product.prerequisiteMatchMode')"
            :validate-status="fieldError('prerequisite_match_mode') ? 'error' : undefined"
            :help="fieldError('prerequisite_match_mode')"
          >
            <a-select
              v-model="form.product.prerequisite_match_mode"
              :options="prerequisiteMatchOptions"
            />
          </a-form-item>

          <a-space direction="vertical" fill :size="12">
            <a-card
              v-for="(prerequisite, index) in form.product.prerequisites.filter((item) => !item._destroy)"
              :key="prerequisite.id || `new-${index}`"
              :bordered="true"
              size="small"
            >
              <a-grid
                :cols="{ xs: 1, sm: 2 }"
                :col-gap="12"
                :row-gap="4"
                align="end"
              >
                <a-grid-item>
                  <a-form-item
                    :label="t('admin.forms.product.prerequisiteProduct')"
                    hide-asterisk
                  >
                    <a-select
                      :model-value="prerequisite.required_product_id == null ? '' : String(prerequisite.required_product_id)"
                      :options="prerequisiteProductOptions"
                      allow-search
                      @update:model-value="(value: string) => prerequisite.required_product_id = value ? Number(value) : null"
                    />
                  </a-form-item>
                </a-grid-item>
                <a-grid-item>
                  <a-form-item
                    :label="t('admin.forms.product.prerequisiteMode')"
                    hide-asterisk
                  >
                    <a-space>
                      <a-select
                        v-model="prerequisite.requirement_mode"
                        :options="requirementModeOptions"
                        class="min-w-48"
                      />
                      <a-button
                        html-type="button"
                        status="danger"
                        @click="removePrerequisite(prerequisite)"
                      >
                        {{ t('admin.ui.remove') }}
                      </a-button>
                    </a-space>
                  </a-form-item>
                </a-grid-item>
              </a-grid>
            </a-card>
          </a-space>
        </a-card>

        <a-card :bordered="true">
          <a-alert
            :title="t('admin.forms.product.fulfillmentProviderTitle')"
            :content="t('admin.forms.product.fulfillmentProviderHint')"
            type="info"
            class="mb-4"
          />
          <a-form-item :label="t('admin.forms.product.fulfillmentProvider')">
            <a-select
              v-model="fulfillmentProviderId"
              :options="fulfillmentProviderOptions"
              allow-search
            />
          </a-form-item>
          <a-divider />
          <a-form-item
            field="image_url"
            :label="t('admin.forms.product.imageUrl')"
            :validate-status="fieldError('image_url') ? 'error' : undefined"
            :help="fieldError('image_url')"
          >
            <a-input
              v-model="form.product.image_url"
              placeholder="https://example.com/image.png"
              allow-clear
            />
          </a-form-item>

          <a-form-item
            v-if="uploadUrl"
            :label="t('admin.forms.product.uploadCover')"
          >
            <a-upload
              accept="image/*"
              :auto-upload="false"
              :show-file-list="false"
              :before-upload="beforeCoverUpload"
            >
              <template #upload-button>
                <a-button html-type="button">
                  {{ t('admin.forms.product.selectCover') }}
                </a-button>
              </template>
            </a-upload>
          </a-form-item>

          <a-form-item
            field="gallery_urls"
            :label="t('admin.forms.product.galleryUrls')"
            :validate-status="fieldError('gallery_urls') ? 'error' : undefined"
            :help="fieldError('gallery_urls')"
          >
            <a-textarea
              v-model="form.product.gallery_urls"
              :auto-size="{ minRows: 3, maxRows: 8 }"
              placeholder="https://example.com/1.png&#10;https://example.com/2.png"
            />
          </a-form-item>

          <template v-if="imagePackOptions.length > 1">
            <a-divider />
            <a-form-item :label="t('admin.forms.product.imagePackSelect')">
              <a-select
                v-model="imagePackId"
                :options="imagePackOptions"
                allow-search
              />
            </a-form-item>
            <a-form-item
              v-if="imagePackId"
              :label="t('admin.forms.product.imagePackTexture')"
              :help="imagePackPreviewUrl ? t('admin.forms.product.imagePackPreview') : undefined"
            >
              <a-space direction="vertical" fill>
                <a-input
                  v-model="imageTexture"
                  :placeholder="t('admin.forms.product.imagePackTexturePlaceholder')"
                  allow-clear
                />
                <a-image
                  v-if="imagePackPreviewUrl"
                  :src="imagePackPreviewUrl"
                  :width="64"
                  :height="64"
                  fit="contain"
                />
              </a-space>
            </a-form-item>
          </template>
        </a-card>

        <a-card :bordered="true">
          <a-form-item
            field="fulfillment_config"
            :label="t('admin.forms.product.fulfillmentConfig')"
            :validate-status="fieldError('fulfillment_config') ? 'error' : undefined"
            :help="fieldError('fulfillment_config')"
          >
            <a-textarea
              v-model="form.product.fulfillment_config"
              :auto-size="{ minRows: 6, maxRows: 16 }"
              class="font-mono text-xs"
              placeholder='{"download_url":"https://example.com/file.zip","commands":["give {player} diamond 1"]}'
            />
          </a-form-item>
        </a-card>

        <a-card :bordered="true">
          <a-grid :cols="{ xs: 1, sm: 2 }" :col-gap="16" :row-gap="4">
            <a-grid-item>
              <a-form-item
                field="version"
                :label="t('admin.forms.product.version')"
                :validate-status="fieldError('version') ? 'error' : undefined"
                :help="fieldError('version')"
              >
                <a-input v-model="form.product.version" placeholder="1.0.0" allow-clear />
              </a-form-item>
            </a-grid-item>
            <a-grid-item>
              <a-form-item
                field="changelog"
                :label="t('admin.forms.product.changelog')"
                :validate-status="fieldError('changelog') ? 'error' : undefined"
                :help="fieldError('changelog')"
              >
                <a-textarea
                  v-model="form.product.changelog"
                  :auto-size="{ minRows: 3, maxRows: 8 }"
                  :placeholder="t('admin.forms.product.changelogPlaceholder')"
                />
              </a-form-item>
            </a-grid-item>
          </a-grid>

          <a-form-item
            field="seo_title"
            :label="t('admin.forms.product.seoTitle')"
            :validate-status="fieldError('seo_title') ? 'error' : undefined"
            :help="fieldError('seo_title')"
          >
            <a-input v-model="form.product.seo_title" allow-clear />
          </a-form-item>
          <a-form-item
            field="seo_description"
            :label="t('admin.forms.product.seoDescription')"
            :validate-status="fieldError('seo_description') ? 'error' : undefined"
            :help="fieldError('seo_description')"
          >
            <a-textarea
              v-model="form.product.seo_description"
              :auto-size="{ minRows: 2, maxRows: 6 }"
              allow-clear
            />
          </a-form-item>
        </a-card>

        <a-card
          :title="t('admin.forms.product.variants')"
          :bordered="true"
        >
          <template #extra>
            <a-button html-type="button" size="small" @click="addVariant">
              {{ t('admin.forms.product.addVariant') }}
            </a-button>
          </template>

          <a-space direction="vertical" fill :size="12">
            <a-card
              v-for="(variant, index) in form.product.variants.filter((item: { _destroy?: boolean }) => !item._destroy)"
              :key="variant.id || index"
              :bordered="true"
              size="small"
            >
              <a-grid
                :cols="{ xs: 1, sm: 2, lg: 4 }"
                :col-gap="12"
                :row-gap="12"
                align="center"
              >
                <a-grid-item>
                  <a-input v-model="variant.name" :placeholder="t('admin.common.name')" />
                </a-grid-item>
                <a-grid-item>
                  <a-input v-model="variant.sku" :placeholder="t('admin.forms.product.sku')" />
                </a-grid-item>
                <a-grid-item>
                  <a-input-number
                    v-model="variant.price_cents"
                    :placeholder="t('admin.forms.product.priceCents')"
                    class="w-full"
                  />
                </a-grid-item>
                <a-grid-item>
                  <a-space>
                    <a-input-number
                      v-model="variant.stock"
                      :placeholder="t('admin.forms.product.stock')"
                      class="w-full"
                    />
                    <a-button
                      html-type="button"
                      status="danger"
                      @click="removeVariant(variant)"
                    >
                      {{ t('admin.ui.delete') }}
                    </a-button>
                  </a-space>
                </a-grid-item>
              </a-grid>
            </a-card>
          </a-space>
        </a-card>

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
