<script setup lang="ts">
import { ref } from 'vue'
import { useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Badge from '@/components/ui/Badge.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import { routes } from '@/lib/routes'
import { router } from '@inertiajs/vue3'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: PortalLayout })

export interface SavedAddress {
  id: number
  label: string | null
  summary: string
  name: string
  phone: string
  line1: string
  line2: string | null
  city: string
  province: string
  postal_code: string | null
  default_address: boolean
  make_default_url: string
  update_url: string
  delete_url: string
}

defineProps<{
  addresses: SavedAddress[]
}>()

const editingId = ref<number | null>(null)
const editForm = useForm({
  address: {
    label: '',
    name: '',
    phone: '',
    line1: '',
    line2: '',
    city: '',
    province: '',
    postal_code: '',
  },
  make_default: false,
})

const form = useForm({
  address: {
    label: '',
    name: '',
    phone: '',
    line1: '',
    line2: '',
    city: '',
    province: '',
    postal_code: '',
  },
  make_default: false,
})

function submit() {
  form.post(routes.storeShippingAddresses, {
    preserveScroll: true,
    onSuccess: () => {
      form.reset()
      form.make_default = false
    },
  })
}

function startEdit(address: SavedAddress) {
  editingId.value = address.id
  editForm.address = {
    label: address.label || '',
    name: address.name,
    phone: address.phone,
    line1: address.line1,
    line2: address.line2 || '',
    city: address.city,
    province: address.province,
    postal_code: address.postal_code || '',
  }
  editForm.make_default = address.default_address
}

function submitEdit(url: string) {
  editForm.patch(url, {
    preserveScroll: true,
    onSuccess: () => { editingId.value = null },
  })
}

function makeDefault(url: string) {
  router.post(url, {}, { preserveScroll: true })
}

async function removeAddress(url: string) {
  const ok = await confirm({
    title: '删除地址',
    message: '确定删除此地址？',
    confirmLabel: '删除',
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(url, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '商城', href: routes.store },
    { label: '收货地址', current: true },
  ]" />

  <PageHeader title="收货地址" subtitle="管理常用收货地址，结账时可快速选择" />

  <div v-if="addresses.length" class="mb-8 space-y-3">
    <div
      v-for="address in addresses"
      :key="address.id"
      class="rounded-lg border p-4"
    >
      <template v-if="editingId === address.id">
        <form class="space-y-3" @submit.prevent="submitEdit(address.update_url)">
          <div class="space-y-2">
            <Label>地址标签</Label>
            <Input v-model="editForm.address.label" />
          </div>
          <div class="grid gap-3 sm:grid-cols-2">
            <Input v-model="editForm.address.name" placeholder="收件人" required />
            <Input v-model="editForm.address.phone" placeholder="手机号" required />
          </div>
          <Input v-model="editForm.address.line1" placeholder="地址" required />
          <Input v-model="editForm.address.line2" placeholder="地址补充" />
          <div class="grid gap-3 sm:grid-cols-3">
            <Input v-model="editForm.address.province" placeholder="省/州" required />
            <Input v-model="editForm.address.city" placeholder="城市" required />
            <Input v-model="editForm.address.postal_code" placeholder="邮编" />
          </div>
          <label class="flex items-center gap-2 text-sm">
            <Checkbox v-model="editForm.make_default" />
            设为默认地址
          </label>
          <div class="flex gap-2">
            <Button type="submit" size="sm" :disabled="editForm.processing">保存</Button>
            <Button type="button" size="sm" variant="outline" @click="editingId = null">取消</Button>
          </div>
        </form>
      </template>
      <template v-else>
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0 flex-1 text-sm">
            <div class="mb-1 flex flex-wrap items-center gap-2">
              <span class="font-medium">{{ address.name }}</span>
              <span class="text-muted-foreground">{{ address.phone }}</span>
              <Badge v-if="address.default_address" variant="secondary">默认</Badge>
              <span v-if="address.label" class="text-xs text-muted-foreground">{{ address.label }}</span>
            </div>
            <p class="text-muted-foreground">
              {{ address.province }} {{ address.city }} {{ address.line1 }}
              <span v-if="address.line2"> {{ address.line2 }}</span>
              <span v-if="address.postal_code">（{{ address.postal_code }}）</span>
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button type="button" size="sm" variant="outline" @click="startEdit(address)">编辑</Button>
            <Button v-if="!address.default_address" type="button" size="sm" variant="outline" @click="makeDefault(address.make_default_url)">
              设为默认
            </Button>
            <Button type="button" size="sm" variant="outline" @click="removeAddress(address.delete_url)">删除</Button>
          </div>
        </div>
      </template>
    </div>
  </div>
  <p v-else class="mb-8 text-sm text-muted-foreground">暂无保存的地址。</p>

  <form class="max-w-xl space-y-4 rounded-lg border p-4" @submit.prevent="submit">
    <h2 class="text-sm font-semibold">添加新地址</h2>
    <div class="space-y-2">
      <Label for="addr_label">地址标签（可选）</Label>
      <Input id="addr_label" v-model="form.address.label" placeholder="例如：家、公司" />
    </div>
    <div class="grid gap-3 sm:grid-cols-2">
      <div class="space-y-2">
        <Label for="addr_name">收件人</Label>
        <Input id="addr_name" v-model="form.address.name" required />
      </div>
      <div class="space-y-2">
        <Label for="addr_phone">手机号</Label>
        <Input id="addr_phone" v-model="form.address.phone" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="addr_line1">地址</Label>
      <Input id="addr_line1" v-model="form.address.line1" required />
    </div>
    <div class="space-y-2">
      <Label for="addr_line2">地址补充（可选）</Label>
      <Input id="addr_line2" v-model="form.address.line2" />
    </div>
    <div class="grid gap-3 sm:grid-cols-3">
      <div class="space-y-2">
        <Label for="addr_province">省/州</Label>
        <Input id="addr_province" v-model="form.address.province" required />
      </div>
      <div class="space-y-2">
        <Label for="addr_city">城市</Label>
        <Input id="addr_city" v-model="form.address.city" required />
      </div>
      <div class="space-y-2">
        <Label for="addr_postal">邮编</Label>
        <Input id="addr_postal" v-model="form.address.postal_code" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.make_default" />
      设为默认地址
    </label>
    <Button type="submit" :disabled="form.processing">保存地址</Button>
  </form>
</template>
