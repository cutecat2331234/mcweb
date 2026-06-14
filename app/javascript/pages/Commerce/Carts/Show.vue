<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface CartItem {
  id: number
  product_name: string
  variant_name: string | null
  quantity: number
  unit_price_label: string
  total_label: string
}

const props = defineProps<{
  items: CartItem[]
  subtotalLabel: string
  loggedIn: boolean
}>()

function updateQuantity(itemId: number, quantity: number) {
  router.patch(routes.storeCart, { item_id: itemId, quantity })
}

function removeItem(itemId: number) {
  router.patch(routes.storeCart, { item_id: itemId, quantity: 0 })
}
</script>

<template>
  <PageHeader title="购物车" />

  <div v-if="items.length" class="space-y-6">
    <div class="rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>商品</TableHead>
            <TableHead>数量</TableHead>
            <TableHead>单价</TableHead>
            <TableHead>小计</TableHead>
            <TableHead />
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="item in items" :key="item.id">
            <TableCell>
              {{ item.product_name }}
              <span v-if="item.variant_name" class="text-muted-foreground"> — {{ item.variant_name }}</span>
            </TableCell>
            <TableCell>
              <input
                type="number"
                :value="item.quantity"
                min="1"
                class="w-16 rounded-md border px-2 py-1 text-sm"
                @change="updateQuantity(item.id, Number(($event.target as HTMLInputElement).value))"
              >
            </TableCell>
            <TableCell>{{ item.unit_price_label }}</TableCell>
            <TableCell>{{ item.total_label }}</TableCell>
            <TableCell>
              <Button variant="ghost" size="sm" type="button" @click="removeItem(item.id)">移除</Button>
            </TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>

    <p class="font-medium">合计：{{ subtotalLabel }}</p>

    <div v-if="loggedIn" class="flex gap-3">
      <Button as-child>
        <Link :href="routes.storeCheckout">去结算</Link>
      </Button>
    </div>
    <div v-else class="space-y-3">
      <p class="text-sm text-muted-foreground">请先登录后再结账。</p>
      <Button as-child variant="outline">
        <Link :href="routes.signIn">登录</Link>
      </Button>
    </div>
  </div>

  <div v-else class="space-y-4">
    <p class="text-sm text-muted-foreground">购物车是空的。</p>
    <Button as-child variant="outline">
      <Link :href="routes.store">浏览商品</Link>
    </Button>
  </div>
</template>
