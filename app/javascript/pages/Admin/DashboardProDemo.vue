<script setup lang="ts">
import { computed, type Component } from 'vue'
import {
  IconClockCircle,
  IconGift,
  IconSafe,
  IconUser,
} from '@arco-design/web-vue/es/icon'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const props = withDefaults(
  defineProps<{
    title?: string
    subtitle?: string
  }>(),
  {
    title: 'Overview',
    subtitle: 'Arco Design layout, cards, and table (demo data)',
  },
)

type Accent = 'primary' | 'warning' | 'info' | 'success'

interface StatCard {
  key: string
  label: string
  value: string
  icon: Component
  accent: Accent
  hint: string
  hintColor: string
}

const subtitle = computed(() =>
  props.subtitle
    .replaceAll('Element Plus', 'Arco Design')
    .replaceAll('EP ', 'Arco '),
)

const stats: StatCard[] = [
  {
    key: 'orders',
    label: 'Total orders',
    value: '1,284',
    icon: IconGift,
    accent: 'primary',
    hint: '+12.5%',
    hintColor: 'green',
  },
  {
    key: 'pending',
    label: 'Pending',
    value: '23',
    icon: IconClockCircle,
    accent: 'warning',
    hint: 'Needs attention',
    hintColor: 'orangered',
  },
  {
    key: 'users',
    label: 'Registered users',
    value: '5,672',
    icon: IconUser,
    accent: 'info',
    hint: '+3.2%',
    hintColor: 'arcoblue',
  },
  {
    key: 'revenue',
    label: 'Monthly revenue',
    value: '¥48,690',
    icon: IconSafe,
    accent: 'success',
    hint: '+8.1%',
    hintColor: 'green',
  },
]

interface RecentOrder {
  order_number: string
  customer: string
  status: string
  status_label: string
  total: string
}

const recentOrders: RecentOrder[] = [
  { order_number: 'MC-20260717-0021', customer: 'SteveCrafter', status: 'completed', status_label: 'Completed', total: '¥128.00' },
  { order_number: 'MC-20260717-0020', customer: 'EnderQueen', status: 'processing', status_label: 'Processing', total: '¥32.00' },
  { order_number: 'MC-20260717-0018', customer: 'RedstoneGuru', status: 'pending', status_label: 'Pending', total: '¥512.00' },
  { order_number: 'MC-20260716-0099', customer: 'PixelKnight', status: 'paid', status_label: 'Paid', total: '¥99.00' },
  { order_number: 'MC-20260716-0095', customer: 'CreeperSlayer', status: 'cancelled', status_label: 'Cancelled', total: '¥156.00' },
  { order_number: 'MC-20260716-0090', customer: 'MobHunter', status: 'refunded', status_label: 'Refunded', total: '¥74.00' },
]

const columns = [
  { title: 'Order', dataIndex: 'order_number', width: 190 },
  { title: 'Customer', dataIndex: 'customer', width: 160 },
  { title: 'Status', dataIndex: 'status', slotName: 'status', width: 130 },
  { title: 'Total', dataIndex: 'total', slotName: 'total', width: 130 },
]

function statusColor(status: string) {
  if (status === 'paid' || status === 'completed') return 'green'
  if (status === 'pending' || status === 'processing') return 'orangered'
  if (status === 'cancelled') return 'red'
  if (status === 'refunded') return 'arcoblue'
  return 'gray'
}
</script>

<template>
  <a-page-header :title="title" :subtitle="subtitle" :show-back="false" />

  <a-alert type="info" show-icon class="mb-4">
    This compatibility demo now uses the same Arco Design shell and components as every admin page.
    It contains static data and does not read or write the database.
  </a-alert>

  <a-grid :cols="{ xs: 1, sm: 2, lg: 4 }" :col-gap="16" :row-gap="16" class="mb-4">
    <a-grid-item v-for="stat in stats" :key="stat.key">
      <a-card class="arco-stat-card" :bordered="false">
        <div class="stat-card-body">
          <div class="arco-stat-card__icon" :class="`arco-stat-card__icon--${stat.accent}`">
            <component :is="stat.icon" />
          </div>
          <a-statistic :title="stat.label" :value="stat.value" />
        </div>
        <a-tag :color="stat.hintColor" class="mt-3">{{ stat.hint }}</a-tag>
      </a-card>
    </a-grid-item>
  </a-grid>

  <a-card title="Recent orders" :bordered="true">
    <template #extra><a-tag color="arcoblue">Demo data</a-tag></template>
    <a-table
      :columns="columns"
      :data="recentOrders"
      row-key="order_number"
      :pagination="false"
      :scroll="{ x: 620 }"
    >
      <template #status="{ record }">
        <a-tag :color="statusColor(record.status)">{{ record.status_label }}</a-tag>
      </template>
      <template #total="{ record }">
        <a-typography-text strong>{{ record.total }}</a-typography-text>
      </template>
    </a-table>
  </a-card>
</template>

<style scoped>
.stat-card-body {
  display: flex;
  align-items: center;
  gap: 14px;
}
</style>
