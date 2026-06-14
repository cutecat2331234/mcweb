<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Label from '@/components/ui/Label.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface CheckoutItem {
  product_name: string
  quantity: number
  total_label: string
}

export interface ProviderOption {
  value: string
  label: string
}

const props = defineProps<{
  items: CheckoutItem[]
  subtotalLabel: string
  providers: ProviderOption[]
  defaultProvider?: string
}>()

const form = useForm({
  checkout: { provider: props.defaultProvider || props.providers[0]?.value || 'fake' },
})
</script>

<template>
  <PageHeader title="结账" />

  <div v-if="items.length" class="max-w-2xl space-y-6">
    <div class="rounded-lg border">
      <Table>
        <TableHeader><TableRow><TableHead>商品</TableHead><TableHead>数量</TableHead><TableHead>小计</TableHead></TableRow></TableHeader>
        <TableBody>
          <TableRow v-for="(item, index) in items" :key="index">
            <TableCell>{{ item.product_name }}</TableCell>
            <TableCell>{{ item.quantity }}</TableCell>
            <TableCell>{{ item.total_label }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <p class="font-medium">合计：{{ subtotalLabel }}</p>

    <form class="space-y-4" @submit.prevent="form.post(routes.storeCheckout)">
      <div class="space-y-2">
        <Label for="provider">支付方式</Label>
        <select id="provider" v-model="form.checkout.provider" class="flex h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm">
          <option v-for="provider in providers" :key="provider.value" :value="provider.value">{{ provider.label }}</option>
        </select>
      </div>
      <Button type="submit" :disabled="form.processing">立即支付</Button>
    </form>
  </div>

  <div v-else class="space-y-4">
    <p class="text-sm text-muted-foreground">购物车是空的。</p>
    <Button as-child variant="outline">
      <Link :href="routes.storeCart">查看购物车</Link>
    </Button>
  </div>
</template>
