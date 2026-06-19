<script setup lang="ts">
import { reactive, watch, ref, computed } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Select from '@/components/ui/Select.vue'
import { routes } from '@/lib/routes'
import { prompt } from '@/lib/usePrompt'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

const props = defineProps<{
  products: Array<{
    id: string
    name: string
    slug: string
    price_label: string
    compare_at_label?: string | null
    on_sale?: boolean
    discount_label?: string | null
    url: string
    in_stock?: boolean
    low_stock?: boolean
    wishlist_url?: string
    add_to_cart_url?: string
    saved_variant_name?: string
    price_alert_url?: string
    has_price_alert?: boolean
    note?: string
    update_note_url?: string
    coming_soon?: boolean
    available_at_label?: string | null
    availability_alert_url?: string
    has_availability_alert?: boolean
    availability_alert_unsubscribe_url?: string
    compare_url?: string
    compared?: boolean
  }>
  shareUrl: string | null
  addAllToCartUrl?: string
  compareCount?: number
  wishlistImportCompareUrl?: string
  wishlistImportableCount?: number
  filters?: { in_stock: boolean; on_sale: boolean; coming_soon: boolean; sort: string }
  totalCount?: number
  filteredCount?: number
  savedFilterPresets?: Array<{ id: number; name: string; url: string; public_share_url?: string | null; delete_url: string }>
  saveFilterPresetUrl?: string
}>()

const saveName = ref('')
const saving = ref(false)
const saveError = ref('')

const wishlistSortOptions = computed(() => [
  { value: 'newest', label: t('commerce.wishlist.sortNewest') },
  { value: 'price_asc', label: t('commerce.wishlist.sortPriceAsc') },
  { value: 'price_desc', label: t('commerce.wishlist.sortPriceDesc') },
  { value: 'name', label: t('commerce.wishlist.sortName') },
])

const noteDrafts = reactive<Record<string, string>>({})

watch(() => props.products, (list) => {
  for (const product of list) {
    if (!(product.id in noteDrafts)) noteDrafts[product.id] = product.note || ''
  }
}, { immediate: true })

const hasActiveFilters = () =>
  !!(props.filters?.in_stock || props.filters?.on_sale || props.filters?.coming_soon || (props.filters?.sort && props.filters.sort !== 'newest'))

function applyFilters(overrides: Partial<{ in_stock: boolean; on_sale: boolean; coming_soon: boolean; sort: string }> = {}) {
  const f = props.filters || { in_stock: false, on_sale: false, coming_soon: false, sort: 'newest' }
  const next = { ...f, ...overrides }
  router.get(routes.storeWishlist, {
    in_stock: next.in_stock ? '1' : undefined,
    on_sale: next.on_sale ? '1' : undefined,
    coming_soon: next.coming_soon ? '1' : undefined,
    sort: next.sort !== 'newest' ? next.sort : undefined,
  }, { preserveState: true })
}

function clearFilters() {
  router.get(routes.storeWishlist, {}, { preserveState: true })
}

function toggleFilter(key: 'in_stock' | 'on_sale' | 'coming_soon') {
  const f = props.filters || { in_stock: false, on_sale: false, coming_soon: false, sort: 'newest' }
  const next = !f[key]
  const overrides: Partial<{ in_stock: boolean; on_sale: boolean; coming_soon: boolean }> = { [key]: next }
  if (key === 'coming_soon' && next) overrides.in_stock = false
  if (key === 'in_stock' && next) overrides.coming_soon = false
  applyFilters(overrides)
}

async function saveFilterPreset() {
  if (!props.saveFilterPresetUrl || !saveName.value.trim()) return
  saving.value = true
  saveError.value = ''
  const f = props.filters || { in_stock: false, on_sale: false, coming_soon: false, sort: 'newest' }
  try {
    const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
    const response = await fetch(props.saveFilterPresetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-CSRF-Token': token,
      },
      credentials: 'same-origin',
      body: JSON.stringify({
        wishlist_filter_preset: {
          name: saveName.value.trim(),
          filters: {
            in_stock: f.in_stock,
            on_sale: f.on_sale,
            coming_soon: f.coming_soon,
            sort: f.sort,
          },
        },
      }),
    })
    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      saveError.value = data.error || t('commerce.wishlist.saveFailed')
      return
    }
    saveName.value = ''
    router.reload({ only: ['savedFilterPresets'] })
  } finally {
    saving.value = false
  }
}

async function deleteFilterPreset(deleteUrl: string) {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content || ''
  await fetch(deleteUrl, {
    method: 'DELETE',
    headers: { 'X-CSRF-Token': token, Accept: 'application/json' },
    credentials: 'same-origin',
  })
  router.reload({ only: ['savedFilterPresets'] })
}

async function copyPublicShare(url: string) {
  try {
    await navigator.clipboard.writeText(new URL(url, window.location.origin).href)
    alert(t('commerce.wishlist.publicShareCopied'))
  } catch {
    await prompt({
      title: t('commerce.wishlist.copyShareLinkTitle'),
      defaultValue: url,
    })
  }
}

function importToCompare() {
  if (!props.wishlistImportCompareUrl) return
  router.post(props.wishlistImportCompareUrl, {}, { preserveScroll: true })
}

function addAllToCart() {
  if (!props.addAllToCartUrl) return
  router.post(props.addAllToCartUrl)
}

function addToCart(url: string) {
  router.post(url)
}

function removeFromWishlist(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function togglePriceAlert(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function subscribeAvailabilityAlert(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function unsubscribeAvailabilityAlert(url: string) {
  router.delete(url, { preserveScroll: true })
}

function toggleCompare(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

function saveNote(product: { id: string; update_note_url?: string }) {
  if (!product.update_note_url) return
  router.patch(product.update_note_url, { note: noteDrafts[product.id] || '' }, { preserveScroll: true })
}

async function copyShareLink() {
  if (!props.shareUrl) return
  try {
    await navigator.clipboard.writeText(props.shareUrl)
    alert(t('commerce.wishlist.shareLinkCopied'))
  } catch {
    await prompt({
      title: t('commerce.wishlist.copyLinkPromptTitle'),
      defaultValue: props.shareUrl,
    })
  }
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('commerce.wishlist.breadcrumbHome'), href: routes.home },
    { label: t('commerce.wishlist.breadcrumbStore'), href: routes.store },
    { label: t('commerce.wishlist.breadcrumbWishlist'), current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader :title="t('commerce.wishlist.title')" />
    <div class="flex gap-2">
      <Button
        v-if="wishlistImportCompareUrl && wishlistImportableCount"
        type="button"
        variant="secondary"
        size="sm"
        @click="importToCompare"
      >
        {{ t('commerce.wishlist.importCompare', { count: wishlistImportableCount }) }}
      </Button>
      <Button as-child variant="outline" size="sm">
        <Link :href="routes.storeCompare">{{ t('commerce.wishlist.compareList') }}{{ compareCount ? ` (${compareCount})` : '' }}</Link>
      </Button>
      <Button v-if="addAllToCartUrl && products.length" type="button" size="sm" @click="addAllToCart">{{ t('commerce.wishlist.addAllToCart') }}</Button>
      <Button v-if="shareUrl" type="button" variant="outline" size="sm" @click="copyShareLink">{{ t('commerce.wishlist.copyShareLink') }}</Button>
      <Button type="button" variant="outline" size="sm" @click="router.post(routes.storeWishlistShare)">{{ t('commerce.wishlist.generateShareLink') }}</Button>
    </div>
  </div>
  <p v-if="shareUrl" class="mb-4 text-xs text-muted-foreground break-all">{{ shareUrl }}</p>

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <Button type="button" size="sm" :variant="filters?.in_stock ? 'default' : 'outline'" @click="toggleFilter('in_stock')">
      {{ t('commerce.wishlist.inStockOnly') }}
    </Button>
    <Button type="button" size="sm" :variant="filters?.on_sale ? 'default' : 'outline'" @click="toggleFilter('on_sale')">
      {{ t('commerce.wishlist.onSaleOnly') }}
    </Button>
    <Button type="button" size="sm" :variant="filters?.coming_soon ? 'default' : 'outline'" @click="toggleFilter('coming_soon')">
      {{ t('commerce.wishlist.comingSoon') }}
    </Button>
    <Select
      :model-value="filters?.sort || 'newest'"
      :options="wishlistSortOptions"
      size="sm"
      @update:model-value="(value) => applyFilters({ sort: value })"
    />
    <Button v-if="hasActiveFilters()" type="button" size="sm" variant="ghost" @click="clearFilters">{{ t('commerce.wishlist.clearFilters') }}</Button>
    <span v-if="totalCount !== undefined && filteredCount !== undefined && hasActiveFilters()" class="text-xs text-muted-foreground">
      {{ t('commerce.wishlist.showingCount', { filtered: filteredCount, total: totalCount }) }}
    </span>
  </div>

  <div v-if="saveFilterPresetUrl && hasActiveFilters()" class="mb-4 flex flex-wrap items-end gap-2 rounded-lg border p-3">
    <div class="space-y-1">
      <label class="text-sm font-medium">{{ t('commerce.wishlist.saveCurrentFilter') }}</label>
      <Input v-model="saveName" :placeholder="t('commerce.wishlist.filterNamePlaceholder')" class="w-48" />
    </div>
    <Button type="button" variant="outline" size="sm" :disabled="saving || !saveName.trim()" @click="saveFilterPreset">
      {{ saving ? t('commerce.wishlist.saving') : t('commerce.wishlist.saveFilter') }}
    </Button>
    <p v-if="saveError" class="text-sm text-destructive">{{ saveError }}</p>
  </div>

  <div v-if="savedFilterPresets?.length" class="mb-4 flex flex-wrap gap-2">
    <span class="text-sm text-muted-foreground">{{ t('commerce.wishlist.savedFilters') }}</span>
    <span v-for="preset in savedFilterPresets" :key="preset.id" class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm">
      <Link :href="preset.url" class="hover:underline">{{ preset.name }}</Link>
      <button
        v-if="preset.public_share_url"
        type="button"
        class="text-muted-foreground hover:text-primary"
        :title="t('commerce.wishlist.copyPublicShareTitle')"
        @click="copyPublicShare(preset.public_share_url!)"
      >
        {{ t('commerce.wishlist.share') }}
      </button>
      <button type="button" class="text-muted-foreground hover:text-destructive" @click="deleteFilterPreset(preset.delete_url)">×</button>
    </span>
  </div>

  <div v-if="products.length" class="divide-y rounded-lg border">
    <div v-for="product in products" :key="product.id" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <Badge v-if="product.coming_soon" variant="outline" class="ml-2 text-[10px]">{{ t('commerce.wishlist.comingSoon') }}</Badge>
        <p class="text-sm">
          <span class="font-medium">{{ product.price_label }}</span>
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs text-muted-foreground line-through">{{ product.compare_at_label }}</span>
          <Badge v-if="product.discount_label" variant="outline" class="ml-1 text-[10px]">{{ product.discount_label }}</Badge>
        </p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">{{ t('commerce.wishlist.variant', { name: product.saved_variant_name }) }}</p>
        <div v-if="product.update_note_url" class="mt-2 flex max-w-md gap-2">
          <Input
            v-model="noteDrafts[product.id]"
            :placeholder="t('commerce.wishlist.notePlaceholder')"
            class="h-8 flex-1 text-xs"
            @keydown.enter.prevent="saveNote(product)"
          />
          <Button type="button" size="sm" variant="outline" @click="saveNote(product)">{{ t('commerce.wishlist.saveNote') }}</Button>
        </div>
        <p v-if="product.coming_soon && product.available_at_label" class="text-xs text-muted-foreground">{{ t('commerce.wishlist.availableAt', { at: product.available_at_label }) }}</p>
        <div v-if="product.coming_soon && product.availability_alert_url" class="mt-2">
          <Button
            v-if="!product.has_availability_alert"
            type="button"
            size="sm"
            variant="secondary"
            @click="subscribeAvailabilityAlert(product.availability_alert_url!)"
          >
            {{ t('commerce.wishlist.availabilityAlert') }}
          </Button>
          <Button
            v-else-if="product.availability_alert_unsubscribe_url"
            type="button"
            size="sm"
            variant="outline"
            @click="unsubscribeAvailabilityAlert(product.availability_alert_unsubscribe_url!)"
          >
            {{ t('commerce.wishlist.availabilitySubscribed') }}
          </Button>
        </div>
        <Badge v-else-if="!product.in_stock" variant="default" class="mt-1">{{ t('commerce.wishlist.outOfStock') }}</Badge>
        <Badge v-else-if="product.low_stock" variant="default" class="mt-1">{{ t('commerce.wishlist.lowStock') }}</Badge>
      </div>
      <div class="flex gap-2">
        <Button
          v-if="product.compare_url"
          type="button"
          size="sm"
          :variant="product.compared ? 'outline' : 'secondary'"
          @click="toggleCompare(product.compare_url)"
        >
          {{ product.compared ? t('commerce.wishlist.removeCompare') : t('commerce.wishlist.addCompare') }}
        </Button>
        <Button v-if="product.add_to_cart_url && product.in_stock && !product.coming_soon" type="button" size="sm" @click="addToCart(product.add_to_cart_url)">{{ t('commerce.wishlist.addToCart') }}</Button>
        <Button
          v-if="product.price_alert_url"
          type="button"
          size="sm"
          :variant="product.has_price_alert ? 'outline' : 'secondary'"
          @click="togglePriceAlert(product.price_alert_url)"
        >
          {{ product.has_price_alert ? t('commerce.wishlist.priceAlertOn') : t('commerce.wishlist.priceAlert') }}
        </Button>
        <Button v-if="product.wishlist_url" type="button" variant="outline" size="sm" @click="removeFromWishlist(product.wishlist_url)">{{ t('commerce.wishlist.remove') }}</Button>
        <Button as-child variant="outline" size="sm">
          <Link :href="product.url">{{ t('commerce.wishlist.view') }}</Link>
        </Button>
      </div>
    </div>
  </div>
  <div v-else class="rounded-lg border border-dashed p-8 text-center">
    <p class="text-sm text-muted-foreground">
      {{ hasActiveFilters() ? t('commerce.wishlist.emptyFiltered') : t('commerce.wishlist.empty') }}
    </p>
    <div class="mt-4 flex flex-wrap justify-center gap-2">
      <Button v-if="hasActiveFilters()" type="button" size="sm" variant="outline" @click="clearFilters">{{ t('commerce.wishlist.clearFilters') }}</Button>
      <Button as-child size="sm">
        <Link :href="routes.store">{{ t('commerce.wishlist.browseStore') }}</Link>
      </Button>
      <Button as-child variant="outline" size="sm">
        <Link :href="routes.storeCompare">{{ t('commerce.wishlist.compareList') }}</Link>
      </Button>
    </div>
  </div>
</template>
