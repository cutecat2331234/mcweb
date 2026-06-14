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
  }
  categories: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ product: { ...props.product } })

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
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">保存</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">取消</Link>
      </Button>
    </div>
  </form>
</template>
