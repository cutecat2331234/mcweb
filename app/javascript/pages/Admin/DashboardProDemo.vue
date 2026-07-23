<script setup lang="ts">
/**
 * POC facade — "Overview" rebuilt on Element Plus, mounted at
 * /admin/dashboard_pro_demo and carried by ProLayout so a single screenshot
 * shows the whole unified EP language: EP sidebar + EP top bar + EP card row +
 * EP mini table. Rendered by Admin::DashboardProDemoController with static demo
 * numbers (no DB reads); safe to delete once the redesign is signed off.
 */
import type { Component } from 'vue'
import ProLayout from '@/components/admin-pro/ProLayout.vue'
import {
  AlarmClock,
  ShoppingCartFull,
  UserFilled,
  Wallet,
} from '@element-plus/icons-vue'

defineOptions({ layout: ProLayout })

withDefaults(
  defineProps<{
    title?: string
    subtitle?: string
  }>(),
  {
    title: '概览',
    subtitle: 'Element Plus 布局 + 卡片 + 表格一套语言的门面（演示数据）',
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
  hintType: 'success' | 'info' | 'warning'
}

/* Card-style stat row — 4 KPIs, each with an accent-tinted icon chip and a
 * colored trend tag so the row reads at a glance. */
const stats: StatCard[] = [
  { key: 'orders', label: '总订单', value: '1,284', icon: ShoppingCartFull, accent: 'primary', hint: '+12.5%', hintType: 'success' },
  { key: 'pending', label: '待处理', value: '23', icon: AlarmClock, accent: 'warning', hint: '需跟进', hintType: 'warning' },
  { key: 'users', label: '注册用户', value: '5,672', icon: UserFilled, accent: 'info', hint: '+3.2%', hintType: 'info' },
  { key: 'revenue', label: '本月收入', value: '¥ 48,690', icon: Wallet, accent: 'success', hint: '+8.1%', hintType: 'success' },
]

interface RecentOrder {
  order_number: string
  customer: string
  status: string
  status_label: string
  total: string
}

const recentOrders: RecentOrder[] = [
  { order_number: 'MC-20260717-0021', customer: 'SteveCrafter', status: 'completed', status_label: '已完成', total: '¥ 128.00' },
  { order_number: 'MC-20260717-0020', customer: 'EnderQueen', status: 'processing', status_label: '处理中', total: '¥ 32.00' },
  { order_number: 'MC-20260717-0018', customer: 'RedstoneGuru', status: 'pending', status_label: '待支付', total: '¥ 512.00' },
  { order_number: 'MC-20260716-0099', customer: 'PixelKnight', status: 'paid', status_label: '已支付', total: '¥ 99.00' },
  { order_number: 'MC-20260716-0095', customer: 'CreeperSlayer', status: 'cancelled', status_label: '已取消', total: '¥ 156.00' },
  { order_number: 'MC-20260716-0090', customer: 'MobHunter', status: 'refunded', status_label: '已退款', total: '¥ 74.00' },
]

function statusTagType(raw: string): 'success' | 'warning' | 'danger' | 'info' | 'primary' {
  switch (raw) {
    case 'paid':
    case 'completed':
      return 'success'
    case 'pending':
    case 'processing':
      return 'warning'
    case 'cancelled':
      return 'danger'
    case 'refunded':
      return 'info'
    default:
      return 'primary'
  }
}
</script>

<template>
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-foreground">{{ title }}</h1>
    <p v-if="subtitle" class="mt-1 text-sm text-muted-foreground">{{ subtitle }}</p>
  </div>

  <el-alert
    class="mb-5"
    type="info"
    :closable="false"
    show-icon
    title="Element Plus 后台重做 · POC 概览门面页"
    description="本页用 ProLayout（EP 侧栏 + 顶栏 + 面包屑）承载 EP 卡片统计行与近期订单 mini 表格，展示统一的 Element Plus 设计语言。演示数据，不读数据库，可随时删除。"
  />

  <!-- Stat cards -->
  <el-row :gutter="16" class="stat-row">
    <el-col v-for="s in stats" :key="s.key" :xs="12" :sm="12" :md="6">
      <el-card class="stat-card" shadow="hover" :body-style="{ padding: '18px 20px' }">
        <div class="stat-card__body">
          <div class="stat-card__icon" :class="`stat-card__icon--${s.accent}`">
            <el-icon :size="22"><component :is="s.icon" /></el-icon>
          </div>
          <div class="stat-card__meta">
            <div class="stat-card__label">{{ s.label }}</div>
            <div class="stat-card__value">{{ s.value }}</div>
          </div>
        </div>
        <el-tag :type="s.hintType" effect="light" size="small" round class="stat-card__hint">
          {{ s.hint }}
        </el-tag>
      </el-card>
    </el-col>
  </el-row>

  <!-- Recent orders mini table -->
  <el-card class="recent-card" shadow="never" :body-style="{ padding: '0' }">
    <template #header>
      <div class="recent-card__header">
        <span class="recent-card__title">近期订单</span>
        <el-tag type="info" effect="plain" size="small" round>演示数据</el-tag>
      </div>
    </template>
    <el-table :data="recentOrders" style="width: 100%">
      <el-table-column prop="order_number" label="订单号" min-width="170" />
      <el-table-column prop="customer" label="客户" min-width="130" />
      <el-table-column label="状态" width="110" align="center">
        <template #default="{ row }">
          <el-tag :type="statusTagType((row as RecentOrder).status)" effect="light" round>
            {{ (row as RecentOrder).status_label }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="金额" width="130" align="right">
        <template #default="{ row }">
          <span class="font-medium tabular-nums">{{ (row as RecentOrder).total }}</span>
        </template>
      </el-table-column>
    </el-table>
  </el-card>
</template>

<style scoped>
.stat-row {
  margin-bottom: 20px;
  row-gap: 16px;
}

.stat-card {
  border-radius: 12px;
}
.stat-card__body {
  display: flex;
  align-items: center;
  gap: 14px;
}
.stat-card__icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 46px;
  height: 46px;
  border-radius: 12px;
  flex-shrink: 0;
}
.stat-card__icon--primary {
  color: var(--el-color-primary);
  background: var(--el-color-primary-light-9);
}
.stat-card__icon--warning {
  color: var(--el-color-warning);
  background: var(--el-color-warning-light-9);
}
.stat-card__icon--info {
  color: var(--el-color-info);
  background: var(--el-color-info-light-9);
}
.stat-card__icon--success {
  color: var(--el-color-success);
  background: var(--el-color-success-light-9);
}
.stat-card__label {
  font-size: 13px;
  color: var(--el-text-color-secondary);
}
.stat-card__value {
  font-size: 24px;
  font-weight: 600;
  line-height: 1.2;
  color: var(--el-text-color-primary);
  font-variant-numeric: tabular-nums;
}
.stat-card__hint {
  margin-top: 12px;
}

.recent-card {
  border-radius: 12px;
  overflow: hidden;
}
.recent-card__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.recent-card__title {
  font-size: 15px;
  font-weight: 600;
  color: var(--el-text-color-primary);
}
</style>
