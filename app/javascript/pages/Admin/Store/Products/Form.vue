<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { usePage } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import FileInput from '@/components/ui/FileInput.vue'
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

function submit() {
  if (!storeFeatures.value.physical_products && form.product.product_type === 'physical') {
    form.product.product_type = 'virtual'
  }
  if (!storeFeatures.value.shipping) {
    form.product.requires_shipping = false
  }
  syncImagePackToFulfillmentConfig()
  form.product.prerequisites = form.product.prerequisites.filter(
    (p) => p._destroy || p.required_product_id,
  )
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

onMounted(() => {
  if (!storeFeatures.value.physical_products && form.product.product_type === 'physical') {
    form.product.product_type = 'virtual'
  }
  if (!storeFeatures.value.shipping) {
    form.product.requires_shipping = false
  }
  loadImagePackFromFulfillmentConfig()
})
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('admin.common.name') }}</Label>
      <Input id="name" v-model="form.product.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.common.slugFull') }}</Label>
      <Input id="slug" v-model="form.product.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="summary">{{ t('admin.forms.product.summary') }}</Label>
      <Textarea id="summary" v-model="form.product.summary" rows="2" :placeholder="t('admin.forms.product.summaryPlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.common.description') }}</Label>
      <Textarea id="description" v-model="form.product.description" rows="4" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="product_type">{{ t('admin.forms.product.type') }}</Label>
        <Select id="product_type" v-model="form.product.product_type" :options="productTypeOptions" block />
      </div>
      <div class="space-y-2">
        <Label for="status">{{ t('admin.common.status') }}</Label>
        <Select id="status" v-model="form.product.status" :options="statusOptions" block />
      </div>
    </div>
    <div v-if="form.product.product_type === 'membership'" class="space-y-2">
      <Label for="membership_type">{{ t('admin.forms.product.membershipType') }}</Label>
      <Select
        id="membership_type"
        :model-value="form.product.store_membership_type_id == null ? '' : String(form.product.store_membership_type_id)"
        :options="membershipTypeOptions"
        block
        @update:model-value="updateMembershipTypeId"
      />
    </div>
    <div class="space-y-3 rounded-lg border p-3">
      <div class="flex items-center justify-between">
        <Label>{{ t('admin.forms.product.prerequisites') }}</Label>
        <Button type="button" variant="outline" size="sm" @click="addPrerequisite">{{ t('admin.forms.product.addPrerequisite') }}</Button>
      </div>
      <div class="space-y-2">
        <Label for="prerequisite_match_mode">{{ t('admin.forms.product.prerequisiteMatchMode') }}</Label>
        <Select id="prerequisite_match_mode" v-model="form.product.prerequisite_match_mode" :options="prerequisiteMatchOptions" block />
      </div>
      <div
        v-for="(prerequisite, index) in form.product.prerequisites.filter((p) => !p._destroy)"
        :key="prerequisite.id || `new-${index}`"
        class="grid grid-cols-[1fr_1fr_auto] items-end gap-2"
      >
        <div class="space-y-1">
          <Label>{{ t('admin.forms.product.prerequisiteProduct') }}</Label>
          <Select
            :model-value="prerequisite.required_product_id == null ? '' : String(prerequisite.required_product_id)"
            :options="prerequisiteProductOptions"
            block
            @update:model-value="(v) => prerequisite.required_product_id = v ? Number(v) : null"
          />
        </div>
        <div class="space-y-1">
          <Label>{{ t('admin.forms.product.prerequisiteMode') }}</Label>
          <Select v-model="prerequisite.requirement_mode" :options="requirementModeOptions" block />
        </div>
        <Button type="button" variant="outline" size="sm" @click="removePrerequisite(prerequisite)">{{ t('admin.ui.remove') }}</Button>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="price_cents">{{ t('admin.forms.product.priceCents') }}</Label>
        <Input id="price_cents" v-model.number="form.product.price_cents" type="number" min="0" required />
      </div>
      <div class="space-y-2">
        <Label for="compare_at_price_cents">{{ t('admin.forms.product.comparePrice') }}</Label>
        <Input id="compare_at_price_cents" v-model.number="form.product.compare_at_price_cents" type="number" min="0" :placeholder="t('admin.forms.product.comparePlaceholder')" />
      </div>
      <div class="space-y-2">
        <Label for="stock">{{ t('admin.forms.product.stock') }}</Label>
        <Input id="stock" v-model.number="form.product.stock" type="number" min="0" />
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="available_at">{{ t('admin.forms.product.availableAt') }}</Label>
        <Input id="available_at" v-model="form.product.available_at" type="datetime-local" />
      </div>
      <div class="space-y-2">
        <Label for="unavailable_at">{{ t('admin.forms.product.unavailableAt') }}</Label>
        <Input id="unavailable_at" v-model="form.product.unavailable_at" type="datetime-local" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="category">{{ t('admin.forms.product.category') }}</Label>
      <Select
        id="category"
        :model-value="form.product.store_category_id == null ? '' : String(form.product.store_category_id)"
        :options="categoryOptions"
        block
        @update:model-value="updateCategoryId"
      />
    </div>
    <div class="space-y-2">
      <Label for="purchase_limit">{{ t('admin.forms.product.purchaseLimit') }}</Label>
      <Input id="purchase_limit" v-model.number="form.product.purchase_limit" type="number" min="1" />
    </div>
    <div class="space-y-2">
      <Label for="minimum_quantity">{{ t('admin.forms.product.minQty') }}</Label>
      <Input id="minimum_quantity" v-model.number="form.product.minimum_quantity" type="number" min="1" />
    </div>
    <div class="space-y-2">
      <Label for="maximum_quantity">{{ t('admin.forms.product.maxQty') }}</Label>
      <Input id="maximum_quantity" v-model.number="form.product.maximum_quantity" type="number" min="1" />
    </div>
    <label v-if="storeFeatures.shipping" class="flex items-center gap-2">
      <Checkbox id="requires_shipping" v-model="form.product.requires_shipping" />
      <Label for="requires_shipping">{{ t('admin.forms.product.requiresShipping') }}</Label>
    </label>
    <div class="space-y-2">
      <Label for="image_url">{{ t('admin.forms.product.imageUrl') }}</Label>
      <Input id="image_url" v-model="form.product.image_url" placeholder="https://example.com/image.png" />
      <div v-if="uploadUrl" class="mt-2">
        <Label for="cover_upload">{{ t('admin.forms.product.uploadCover') }}</Label>
        <FileInput id="cover_upload" accept="image/*" :button-label="t('admin.forms.product.selectCover')" @change="uploadCover" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="gallery_urls">{{ t('admin.forms.product.galleryUrls') }}</Label>
      <Textarea id="gallery_urls" v-model="form.product.gallery_urls" rows="3" placeholder="https://example.com/1.png&#10;https://example.com/2.png" />
    </div>
    <div v-if="imagePackOptions.length > 1" class="space-y-3 rounded-lg border p-3">
      <Label>{{ t('admin.forms.product.imagePack') }}</Label>
      <div class="space-y-2">
        <Label for="image_pack">{{ t('admin.forms.product.imagePackSelect') }}</Label>
        <Select id="image_pack" v-model="imagePackId" :options="imagePackOptions" block />
      </div>
      <div v-if="imagePackId" class="space-y-2">
        <Label for="image_texture">{{ t('admin.forms.product.imagePackTexture') }}</Label>
        <Input
          id="image_texture"
          v-model="imageTexture"
          :placeholder="t('admin.forms.product.imagePackTexturePlaceholder')"
        />
        <p v-if="imagePackPreviewUrl" class="text-xs text-muted-foreground">{{ t('admin.forms.product.imagePackPreview') }}</p>
        <img
          v-if="imagePackPreviewUrl"
          :src="imagePackPreviewUrl"
          alt=""
          class="h-16 w-16 rounded border bg-muted object-contain"
          @error="($event.target as HTMLImageElement).style.display = 'none'"
        />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="fulfillment_config">{{ t('admin.forms.product.fulfillmentConfig') }}</Label>
      <Textarea id="fulfillment_config" v-model="form.product.fulfillment_config" rows="6" placeholder='{"download_url":"https://example.com/file.zip","commands":["give {player} diamond 1"]}' />
    </div>
    <label class="flex items-center gap-2">
      <Checkbox id="featured" v-model="form.product.featured" />
      <Label for="featured">{{ t('admin.forms.product.featured') }}</Label>
    </label>
    <label class="flex items-center gap-2">
      <Checkbox id="allow_backorder" v-model="form.product.allow_backorder" />
      <Label for="allow_backorder">{{ t('admin.forms.product.allowBackorder') }}</Label>
    </label>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="version">{{ t('admin.forms.product.version') }}</Label>
        <Input id="version" v-model="form.product.version" placeholder="1.0.0" />
      </div>
      <div class="space-y-2">
        <Label for="changelog">{{ t('admin.forms.product.changelog') }}</Label>
        <Textarea id="changelog" v-model="form.product.changelog" rows="3" :placeholder="t('admin.forms.product.changelogPlaceholder')" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="seo_title">{{ t('admin.forms.product.seoTitle') }}</Label>
      <Input id="seo_title" v-model="form.product.seo_title" />
    </div>
    <div class="space-y-2">
      <Label for="seo_description">{{ t('admin.forms.product.seoDescription') }}</Label>
      <Textarea id="seo_description" v-model="form.product.seo_description" rows="2" />
    </div>

    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <Label>{{ t('admin.forms.product.variants') }}</Label>
        <Button type="button" variant="outline" size="sm" @click="addVariant">{{ t('admin.forms.product.addVariant') }}</Button>
      </div>
      <div
        v-for="(variant, index) in form.product.variants.filter((v: { _destroy?: boolean }) => !v._destroy)"
        :key="index"
        class="grid grid-cols-2 gap-2 rounded-lg border p-3"
      >
        <Input v-model="variant.name" :placeholder="t('admin.common.name')" />
        <Input v-model="variant.sku" :placeholder="t('admin.forms.product.sku')" />
        <Input v-model.number="variant.price_cents" type="number" :placeholder="t('admin.forms.product.priceCents')" />
        <Input v-model.number="variant.stock" type="number" :placeholder="t('admin.forms.product.stock')" />
        <Button type="button" variant="outline" size="sm" class="col-span-2" @click="removeVariant(variant)">{{ t('admin.ui.delete') }}</Button>
      </div>
    </div>

    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
