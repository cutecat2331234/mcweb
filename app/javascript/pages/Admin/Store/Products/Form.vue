<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import FileInput from '@/components/ui/FileInput.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

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
  }
  categories: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
  uploadUrl?: string | null
}>()

const form = useForm({
  product: {
    ...props.product,
    variants: props.product.variants?.length ? [...props.product.variants] : [],
  },
})

const productTypeOptions = computed(() => [
  { value: 'virtual', label: t('admin.forms.product.typeVirtual') },
  { value: 'physical', label: t('admin.forms.product.typePhysical') },
  { value: 'gift_card', label: t('admin.forms.product.typeGiftCard') },
  { value: 'digital', label: t('admin.forms.product.typeDigital') },
])

const statusOptions = computed(() => [
  { value: 'draft', label: t('admin.forms.product.statusDraft') },
  { value: 'active', label: t('admin.forms.product.statusActive') },
  { value: 'archived', label: t('admin.forms.product.statusArchived') },
])

const categoryOptions = computed(() => [
  { value: '', label: t('admin.common.noCategory') },
  ...props.categories.map((cat) => ({ value: String(cat.id), label: cat.name })),
])

function updateCategoryId(value: string) {
  form.product.store_category_id = value ? Number(value) : null
}

function addVariant() {
  form.product.variants.push({ name: '', sku: '', price_cents: form.product.price_cents, stock: null })
}

function removeVariant(index: number) {
  const variant = form.product.variants[index]
  if (variant.id) {
    form.product.variants[index] = { ...variant, _destroy: true } as typeof variant & { _destroy: boolean }
  } else {
    form.product.variants.splice(index, 1)
  }
}

function submit() {
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
    <label class="flex items-center gap-2">
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
    <div class="space-y-2">
      <Label for="seo_title">{{ t('admin.forms.product.seoTitle') }}</Label>
      <Input id="seo_title" v-model="form.product.seo_title" />
    </div>
    <div class="space-y-2">
      <Label for="seo_description">{{ t('admin.forms.product.seoDescription') }}</Label>
      <Textarea id="seo_description" v-model="form.product.seo_description" rows="2" />
    </div>
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
        <Button type="button" variant="outline" size="sm" class="col-span-2" @click="removeVariant(index)">{{ t('admin.ui.delete') }}</Button>
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
