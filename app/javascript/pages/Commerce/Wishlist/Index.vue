<script setup lang="ts">
import { reactive, watch, ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
  savedFilterPresets?: Array<{ id: number; name: string; url: string; delete_url: string }>
  saveFilterPresetUrl?: string
}>()

const saveName = ref('')
const saving = ref(false)
const saveError = ref('')

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
      saveError.value = data.error || '保存失败'
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
    alert('分享链接已复制')
  } catch {
    prompt('复制此链接', props.shareUrl)
  }
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '心愿单', current: true },
  ]" />

  <div class="mb-4 flex items-center justify-between gap-3">
    <PageHeader title="我的心愿单" />
    <div class="flex gap-2">
      <Button
        v-if="wishlistImportCompareUrl && wishlistImportableCount"
        type="button"
        variant="secondary"
        size="sm"
        @click="importToCompare"
      >
        导入对比 ({{ wishlistImportableCount }})
      </Button>
      <Button as-child variant="outline" size="sm">
        <Link :href="routes.storeCompare">商品对比{{ compareCount ? ` (${compareCount})` : '' }}</Link>
      </Button>
      <Button v-if="addAllToCartUrl && products.length" type="button" size="sm" @click="addAllToCart">全部加入购物车</Button>
      <Button v-if="shareUrl" type="button" variant="outline" size="sm" @click="copyShareLink">复制分享链接</Button>
      <Button type="button" variant="outline" size="sm" @click="router.post(routes.storeWishlistShare)">生成分享链接</Button>
    </div>
  </div>
  <p v-if="shareUrl" class="mb-4 text-xs text-muted-foreground break-all">{{ shareUrl }}</p>

  <div class="mb-4 flex flex-wrap items-center gap-2">
    <Button type="button" size="sm" :variant="filters?.in_stock ? 'default' : 'outline'" @click="toggleFilter('in_stock')">
      仅有货
    </Button>
    <Button type="button" size="sm" :variant="filters?.on_sale ? 'default' : 'outline'" @click="toggleFilter('on_sale')">
      促销中
    </Button>
    <Button type="button" size="sm" :variant="filters?.coming_soon ? 'default' : 'outline'" @click="toggleFilter('coming_soon')">
      即将上架
    </Button>
    <select
      :value="filters?.sort || 'newest'"
      class="h-8 rounded-md border px-2 text-xs"
      @change="applyFilters({ sort: ($event.target as HTMLSelectElement).value })"
    >
      <option value="newest">最近添加</option>
      <option value="price_asc">价格从低到高</option>
      <option value="price_desc">价格从高到低</option>
      <option value="name">名称 A-Z</option>
    </select>
    <Button v-if="hasActiveFilters()" type="button" size="sm" variant="ghost" @click="clearFilters">清除筛选</Button>
    <span v-if="totalCount !== undefined && filteredCount !== undefined && hasActiveFilters()" class="text-xs text-muted-foreground">
      显示 {{ filteredCount }} / {{ totalCount }} 件
    </span>
  </div>

  <div v-if="saveFilterPresetUrl && hasActiveFilters()" class="mb-4 flex flex-wrap items-end gap-2 rounded-lg border p-3">
    <div class="space-y-1">
      <label class="text-sm font-medium">保存当前筛选</label>
      <Input v-model="saveName" placeholder="筛选名称" class="w-48" />
    </div>
    <Button type="button" variant="outline" size="sm" :disabled="saving || !saveName.trim()" @click="saveFilterPreset">
      {{ saving ? '保存中…' : '保存筛选' }}
    </Button>
    <p v-if="saveError" class="text-sm text-destructive">{{ saveError }}</p>
  </div>

  <div v-if="savedFilterPresets?.length" class="mb-4 flex flex-wrap gap-2">
    <span class="text-sm text-muted-foreground">已保存：</span>
    <span v-for="preset in savedFilterPresets" :key="preset.id" class="inline-flex items-center gap-1 rounded-full border px-3 py-1 text-sm">
      <Link :href="preset.url" class="hover:underline">{{ preset.name }}</Link>
      <button type="button" class="text-muted-foreground hover:text-destructive" @click="deleteFilterPreset(preset.delete_url)">×</button>
    </span>
  </div>

  <div v-if="products.length" class="divide-y rounded-lg border">
    <div v-for="product in products" :key="product.id" class="flex items-center justify-between gap-4 p-4">
      <div>
        <Link :href="product.url" class="font-medium hover:underline">{{ product.name }}</Link>
        <Badge v-if="product.coming_soon" variant="outline" class="ml-2 text-[10px]">即将上架</Badge>
        <p class="text-sm">
          <span class="font-medium">{{ product.price_label }}</span>
          <span v-if="product.on_sale && product.compare_at_label" class="ml-2 text-xs text-muted-foreground line-through">{{ product.compare_at_label }}</span>
          <Badge v-if="product.discount_label" variant="outline" class="ml-1 text-[10px]">{{ product.discount_label }}</Badge>
        </p>
        <p v-if="product.saved_variant_name" class="text-xs text-muted-foreground">规格：{{ product.saved_variant_name }}</p>
        <div v-if="product.update_note_url" class="mt-2 flex max-w-md gap-2">
          <input
            v-model="noteDrafts[product.id]"
            type="text"
            placeholder="添加备注…"
            class="h-8 flex-1 rounded-md border px-2 text-xs"
            @keydown.enter.prevent="saveNote(product)"
          >
          <Button type="button" size="sm" variant="outline" @click="saveNote(product)">保存备注</Button>
        </div>
        <p v-if="product.coming_soon && product.available_at_label" class="text-xs text-muted-foreground">上架时间：{{ product.available_at_label }}</p>
        <div v-if="product.coming_soon && product.availability_alert_url" class="mt-2">
          <Button
            v-if="!product.has_availability_alert"
            type="button"
            size="sm"
            variant="secondary"
            @click="subscribeAvailabilityAlert(product.availability_alert_url!)"
          >
            上架通知
          </Button>
          <Button
            v-else-if="product.availability_alert_unsubscribe_url"
            type="button"
            size="sm"
            variant="outline"
            @click="unsubscribeAvailabilityAlert(product.availability_alert_unsubscribe_url!)"
          >
            已订阅上架
          </Button>
        </div>
        <Badge v-else-if="!product.in_stock" variant="default" class="mt-1">缺货</Badge>
        <Badge v-else-if="product.low_stock" variant="default" class="mt-1">库存紧张</Badge>
      </div>
      <div class="flex gap-2">
        <Button
          v-if="product.compare_url"
          type="button"
          size="sm"
          :variant="product.compared ? 'outline' : 'secondary'"
          @click="toggleCompare(product.compare_url)"
        >
          {{ product.compared ? '移出对比' : '加入对比' }}
        </Button>
        <Button v-if="product.add_to_cart_url && product.in_stock && !product.coming_soon" type="button" size="sm" @click="addToCart(product.add_to_cart_url)">加入购物车</Button>
        <Button
          v-if="product.price_alert_url"
          type="button"
          size="sm"
          :variant="product.has_price_alert ? 'outline' : 'secondary'"
          @click="togglePriceAlert(product.price_alert_url)"
        >
          {{ product.has_price_alert ? '已订阅降价' : '降价提醒' }}
        </Button>
        <Button v-if="product.wishlist_url" type="button" variant="outline" size="sm" @click="removeFromWishlist(product.wishlist_url)">移除</Button>
        <Button as-child variant="outline" size="sm">
          <Link :href="product.url">查看</Link>
        </Button>
      </div>
    </div>
  </div>
  <div v-else class="rounded-lg border border-dashed p-8 text-center">
    <p class="text-sm text-muted-foreground">
      {{ hasActiveFilters() ? '没有符合筛选条件的商品。' : '心愿单是空的。浏览商城添加喜欢的商品吧。' }}
    </p>
    <div class="mt-4 flex flex-wrap justify-center gap-2">
      <Button v-if="hasActiveFilters()" type="button" size="sm" variant="outline" @click="clearFilters">清除筛选</Button>
      <Button as-child size="sm">
        <Link :href="routes.store">浏览商城</Link>
      </Button>
      <Button as-child variant="outline" size="sm">
        <Link :href="routes.storeCompare">商品对比</Link>
      </Button>
    </div>
  </div>
</template>
