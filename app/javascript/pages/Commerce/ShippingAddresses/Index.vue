<script setup lang="ts">
import { ref } from 'vue'
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
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

const { t } = useI18n()

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
    title: t('commerce.shippingAddresses.deleteTitle'),
    message: t('commerce.shippingAddresses.deleteConfirm'),
    confirmLabel: t('commerce.shippingAddresses.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(url, { preserveScroll: true })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.store'), href: routes.store },
    { label: t('commerce.shippingAddresses.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('commerce.shippingAddresses.title')" :subtitle="t('commerce.shippingAddresses.subtitle')" />

  <div v-if="addresses.length" class="mb-8 space-y-3">
    <div
      v-for="address in addresses"
      :key="address.id"
      class="rounded-lg border p-4"
    >
      <template v-if="editingId === address.id">
        <form class="space-y-3" @submit.prevent="submitEdit(address.update_url)">
          <div class="space-y-2">
            <Label>{{ t('commerce.shippingAddresses.addressLabel') }}</Label>
            <Input v-model="editForm.address.label" />
          </div>
          <div class="grid gap-3 sm:grid-cols-2">
            <Input v-model="editForm.address.name" :placeholder="t('commerce.shippingAddresses.recipient')" required />
            <Input v-model="editForm.address.phone" :placeholder="t('commerce.shippingAddresses.phone')" required />
          </div>
          <Input v-model="editForm.address.line1" :placeholder="t('commerce.shippingAddresses.line1')" required />
          <Input v-model="editForm.address.line2" :placeholder="t('commerce.shippingAddresses.line2')" />
          <div class="grid gap-3 sm:grid-cols-3">
            <Input v-model="editForm.address.province" :placeholder="t('commerce.shippingAddresses.province')" required />
            <Input v-model="editForm.address.city" :placeholder="t('commerce.shippingAddresses.city')" required />
            <Input v-model="editForm.address.postal_code" :placeholder="t('commerce.shippingAddresses.postalCode')" />
          </div>
          <label class="flex items-center gap-2 text-sm">
            <Checkbox v-model="editForm.make_default" />
            {{ t('commerce.shippingAddresses.makeDefault') }}
          </label>
          <div class="flex gap-2">
            <Button type="submit" size="sm" :disabled="editForm.processing">{{ t('commerce.shippingAddresses.save') }}</Button>
            <Button type="button" size="sm" variant="outline" @click="editingId = null">{{ t('commerce.shippingAddresses.cancel') }}</Button>
          </div>
        </form>
      </template>
      <template v-else>
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="min-w-0 flex-1 text-sm">
            <div class="mb-1 flex flex-wrap items-center gap-2">
              <span class="font-medium">{{ address.name }}</span>
              <span class="text-muted-foreground">{{ address.phone }}</span>
              <Badge v-if="address.default_address" variant="secondary">{{ t('commerce.shippingAddresses.defaultBadge') }}</Badge>
              <span v-if="address.label" class="text-xs text-muted-foreground">{{ address.label }}</span>
            </div>
            <p class="text-muted-foreground">
              {{ address.province }} {{ address.city }} {{ address.line1 }}
              <span v-if="address.line2"> {{ address.line2 }}</span>
              <span v-if="address.postal_code">（{{ address.postal_code }}）</span>
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <Button type="button" size="sm" variant="outline" @click="startEdit(address)">{{ t('commerce.shippingAddresses.edit') }}</Button>
            <Button v-if="!address.default_address" type="button" size="sm" variant="outline" @click="makeDefault(address.make_default_url)">
              {{ t('commerce.shippingAddresses.makeDefaultBtn') }}
            </Button>
            <Button type="button" size="sm" variant="outline" @click="removeAddress(address.delete_url)">{{ t('commerce.shippingAddresses.delete') }}</Button>
          </div>
        </div>
      </template>
    </div>
  </div>
  <p v-else class="mb-8 text-sm text-muted-foreground">{{ t('commerce.shippingAddresses.empty') }}</p>

  <form class="max-w-xl space-y-4 rounded-lg border p-4" @submit.prevent="submit">
    <h2 class="text-sm font-semibold">{{ t('commerce.shippingAddresses.addNew') }}</h2>
    <div class="space-y-2">
      <Label for="addr_label">{{ t('commerce.shippingAddresses.addressLabelOptional') }}</Label>
      <Input id="addr_label" v-model="form.address.label" :placeholder="t('commerce.shippingAddresses.addressLabelPlaceholder')" />
    </div>
    <div class="grid gap-3 sm:grid-cols-2">
      <div class="space-y-2">
        <Label for="addr_name">{{ t('commerce.shippingAddresses.recipient') }}</Label>
        <Input id="addr_name" v-model="form.address.name" required />
      </div>
      <div class="space-y-2">
        <Label for="addr_phone">{{ t('commerce.shippingAddresses.phone') }}</Label>
        <Input id="addr_phone" v-model="form.address.phone" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="addr_line1">{{ t('commerce.shippingAddresses.line1') }}</Label>
      <Input id="addr_line1" v-model="form.address.line1" required />
    </div>
    <div class="space-y-2">
      <Label for="addr_line2">{{ t('commerce.shippingAddresses.line2Optional') }}</Label>
      <Input id="addr_line2" v-model="form.address.line2" />
    </div>
    <div class="grid gap-3 sm:grid-cols-3">
      <div class="space-y-2">
        <Label for="addr_province">{{ t('commerce.shippingAddresses.province') }}</Label>
        <Input id="addr_province" v-model="form.address.province" required />
      </div>
      <div class="space-y-2">
        <Label for="addr_city">{{ t('commerce.shippingAddresses.city') }}</Label>
        <Input id="addr_city" v-model="form.address.city" required />
      </div>
      <div class="space-y-2">
        <Label for="addr_postal">{{ t('commerce.shippingAddresses.postalCode') }}</Label>
        <Input id="addr_postal" v-model="form.address.postal_code" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.make_default" />
      {{ t('commerce.shippingAddresses.makeDefault') }}
    </label>
    <Button type="submit" :disabled="form.processing">{{ t('commerce.shippingAddresses.saveAddress') }}</Button>
  </form>
</template>
