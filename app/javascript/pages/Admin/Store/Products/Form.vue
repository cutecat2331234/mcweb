<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  product: {
    public_id?: string
    name: string
    slug: string
    description: string
    product_type: string
    status: string
    price_cents: number
    currency: string
    stock: number | null
    store_category_id: number | null
    purchase_limit: number | null
    image_url: string
    gallery_urls: string
    fulfillment_config: string
    featured?: boolean
    version?: string
    changelog?: string
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

async function uploadCover(event: Event) {
  if (!props.uploadUrl) return
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return
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
      <Label for="name">名称</Label>
      <Input id="name" v-model="form.product.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">标识 (slug)</Label>
      <Input id="slug" v-model="form.product.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="description">描述</Label>
      <Textarea id="description" v-model="form.product.description" rows="4" />
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="product_type">类型</Label>
        <select id="product_type" v-model="form.product.product_type" class="h-9 w-full rounded-md border px-2 text-sm">
          <option value="virtual">虚拟商品</option>
          <option value="physical">实体商品</option>
        </select>
      </div>
      <div class="space-y-2">
        <Label for="status">状态</Label>
        <select id="status" v-model="form.product.status" class="h-9 w-full rounded-md border px-2 text-sm">
          <option value="draft">草稿</option>
          <option value="active">上架</option>
          <option value="archived">归档</option>
        </select>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="price_cents">价格（分）</Label>
        <Input id="price_cents" v-model.number="form.product.price_cents" type="number" min="0" required />
      </div>
      <div class="space-y-2">
        <Label for="stock">库存（空=无限）</Label>
        <Input id="stock" v-model.number="form.product.stock" type="number" min="0" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="category">分类</Label>
      <select id="category" v-model="form.product.store_category_id" class="h-9 w-full rounded-md border px-2 text-sm">
        <option :value="null">无分类</option>
        <option v-for="cat in categories" :key="cat.id" :value="cat.id">{{ cat.name }}</option>
      </select>
    </div>
    <div class="space-y-2">
      <Label for="purchase_limit">限购（空=不限）</Label>
      <Input id="purchase_limit" v-model.number="form.product.purchase_limit" type="number" min="1" />
    </div>
    <div class="space-y-2">
      <Label for="image_url">商品图片 URL</Label>
      <Input id="image_url" v-model="form.product.image_url" placeholder="https://example.com/image.png" />
      <div v-if="uploadUrl" class="mt-2">
        <Label for="cover_upload">或上传封面图</Label>
        <input id="cover_upload" type="file" accept="image/*" class="text-sm" @change="uploadCover" />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="gallery_urls">图库 URL（每行一个）</Label>
      <Textarea id="gallery_urls" v-model="form.product.gallery_urls" rows="3" placeholder="https://example.com/1.png&#10;https://example.com/2.png" />
    </div>
    <div class="space-y-2">
      <Label for="fulfillment_config">发货配置（JSON，可含 download_url、Minecraft 命令等）</Label>
      <Textarea id="fulfillment_config" v-model="form.product.fulfillment_config" rows="6" placeholder='{"download_url":"https://example.com/file.zip","commands":["give {player} diamond 1"]}' />
    </div>
    <div class="flex items-center gap-2">
      <input id="featured" v-model="form.product.featured" type="checkbox" class="rounded border" />
      <Label for="featured">精选商品（首页展示）</Label>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="version">版本号</Label>
        <Input id="version" v-model="form.product.version" placeholder="1.0.0" />
      </div>
      <div class="space-y-2">
        <Label for="changelog">更新日志</Label>
        <Textarea id="changelog" v-model="form.product.changelog" rows="3" placeholder="本次更新内容…" />
      </div>
    </div>

    <div class="space-y-3">
      <div class="flex items-center justify-between">
        <Label>商品变体</Label>
        <Button type="button" variant="outline" size="sm" @click="addVariant">添加变体</Button>
      </div>
      <div
        v-for="(variant, index) in form.product.variants.filter((v: { _destroy?: boolean }) => !v._destroy)"
        :key="index"
        class="grid grid-cols-2 gap-2 rounded-lg border p-3"
      >
        <Input v-model="variant.name" placeholder="名称" />
        <Input v-model="variant.sku" placeholder="SKU" />
        <Input v-model.number="variant.price_cents" type="number" placeholder="价格（分）" />
        <Input v-model.number="variant.stock" type="number" placeholder="库存" />
        <Button type="button" variant="outline" size="sm" class="col-span-2" @click="removeVariant(index)">删除</Button>
      </div>
    </div>

    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
