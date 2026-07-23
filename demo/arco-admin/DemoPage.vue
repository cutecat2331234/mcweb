<script setup lang="ts">
/**
 * Standalone Arco demo page — adapted from app/javascript/pages/Admin/ArcoDemo/Index.vue
 */
import { computed, reactive, ref, type Component } from 'vue'
import { Message } from '@mcweb/ui'
import {
  IconCalendar,
  IconCheckCircle,
  IconCloseCircle,
  IconExclamationCircle,
  IconGift,
  IconSafe,
  IconSearch,
  IconSchedule,
  IconUser,
} from '@arco-design/web-vue/es/icon'
import { demoStats, demoTable, type DemoStat } from './data'

const title = 'Arco UI 范例'
const subtitle = 'Arco Design Vue 组件库 + Arco Pro 布局风格的 McWeb 后台演示（静态数据）'

const statIcons: Record<string, Component> = {
  orders: IconGift,
  pending: IconSchedule,
  users: IconUser,
  revenue: IconSafe,
}

const form = reactive({
  keyword: '',
  status: 'all',
  date: '',
})

const statusOptions = [
  { label: '全部状态', value: 'all' },
  { label: '已完成', value: 'completed' },
  { label: '处理中', value: 'processing' },
  { label: '待支付', value: 'pending' },
]

const modalVisible = ref(false)

const filteredTable = computed(() => {
  let rows = demoTable
  if (form.keyword.trim()) {
    const q = form.keyword.trim().toLowerCase()
    rows = rows.filter(
      (r) => r.order_number.toLowerCase().includes(q) || r.customer.toLowerCase().includes(q),
    )
  }
  if (form.status !== 'all') {
    rows = rows.filter((r) => r.status === form.status)
  }
  return rows
})

const tableColumns = [
  { title: '订单号', dataIndex: 'order_number', width: 180 },
  { title: '客户', dataIndex: 'customer', width: 140 },
  { title: '状态', slotName: 'status', width: 110 },
  { title: '金额', dataIndex: 'total', width: 120 },
  { title: '创建时间', dataIndex: 'created_at', width: 170 },
]

function statusColor(status: string): string {
  switch (status) {
    case 'completed':
    case 'paid':
      return 'green'
    case 'processing':
    case 'pending':
      return 'orangered'
    case 'cancelled':
      return 'red'
    case 'refunded':
      return 'arcoblue'
    default:
      return 'gray'
  }
}

function trendTagColor(type: DemoStat['trend_type']) {
  if (type === 'up') return 'green'
  if (type === 'warn') return 'orangered'
  return 'arcoblue'
}

function onSearch() {
  Message.info(`筛选：${filteredTable.value.length} 条结果`)
}

function onReset() {
  form.keyword = ''
  form.status = 'all'
  form.date = ''
}

function openModal() {
  modalVisible.value = true
}

function onModalOk() {
  modalVisible.value = false
  Message.success('操作已确认（演示）')
}
</script>

<template>
  <div class="arco-demo-page">
    <a-page-header
      :title="title"
      :subtitle="subtitle"
      :show-back="false"
      class="arco-demo-page__header"
    >
      <template #breadcrumb>
        <a-breadcrumb>
          <a-breadcrumb-item>概览</a-breadcrumb-item>
          <a-breadcrumb-item>Arco UI 范例</a-breadcrumb-item>
        </a-breadcrumb>
      </template>
      <template #extra>
        <a-space>
          <a-button @click="onReset">重置</a-button>
          <a-button type="primary" @click="openModal">
            打开弹窗
          </a-button>
        </a-space>
      </template>
    </a-page-header>

    <a-alert type="info" class="arco-demo-page__alert">
      独立前端演示 — 无需 Rails 或 Inertia。展示 Arco Design Vue 的表格、表单、统计卡片与布局能力，数据为静态示例。
    </a-alert>

    <a-row :gutter="16" class="arco-demo-page__stats">
      <a-col v-for="stat in demoStats" :key="stat.key" :xs="12" :sm="12" :md="6" :lg="6">
        <a-card class="arco-stat-card" :bordered="false">
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-3 min-w-0">
              <div class="arco-stat-card__icon" :class="`arco-stat-card__icon--${stat.accent}`">
                <component :is="statIcons[stat.key] ?? IconGift" />
              </div>
              <div class="min-w-0">
                <div class="text-[13px] text-[var(--color-text-3)]">{{ stat.label }}</div>
                <div class="text-2xl font-semibold tabular-nums text-[var(--color-text-1)]">
                  {{ stat.value }}
                </div>
              </div>
            </div>
            <a-tag :color="trendTagColor(stat.trend_type)" size="small">{{ stat.trend }}</a-tag>
          </div>
        </a-card>
      </a-col>
    </a-row>

    <a-card title="筛选表单" class="arco-demo-page__section" :bordered="false">
      <a-form :model="form" layout="inline" class="arco-demo-form">
        <a-form-item field="keyword" label="关键词">
          <a-input v-model="form.keyword" placeholder="订单号 / 客户" allow-clear>
            <template #prefix><icon-search /></template>
          </a-input>
        </a-form-item>
        <a-form-item field="status" label="状态">
          <a-select v-model="form.status" :options="statusOptions" style="width: 160px" />
        </a-form-item>
        <a-form-item field="date" label="日期">
          <a-date-picker v-model="form.date" placeholder="选择日期" style="width: 180px">
            <template #prefix><icon-calendar /></template>
          </a-date-picker>
        </a-form-item>
        <a-form-item>
          <a-space>
            <a-button type="primary" @click="onSearch">查询</a-button>
            <a-button @click="onReset">重置</a-button>
          </a-space>
        </a-form-item>
      </a-form>
    </a-card>

    <a-card class="arco-demo-page__section" :bordered="false">
      <template #title>
        <div class="flex items-center justify-between gap-3">
          <span>近期订单</span>
          <a-tag color="arcoblue" size="small">演示数据</a-tag>
        </div>
      </template>
      <template #extra>
        <a-space>
          <a-button type="outline" status="success" size="small">
            <template #icon><icon-check-circle /></template>
            导出
          </a-button>
          <a-button type="outline" status="warning" size="small">
            <template #icon><icon-exclamation-circle /></template>
            批量处理
          </a-button>
        </a-space>
      </template>
      <a-table
        :columns="tableColumns"
        :data="filteredTable"
        :pagination="{ pageSize: 5, showTotal: true }"
        row-key="id"
        stripe
      >
        <template #status="{ record }">
          <a-tag :color="statusColor(record.status)" size="small">
            {{ record.status_label }}
          </a-tag>
        </template>
      </a-table>
    </a-card>
  </div>

  <a-modal
    v-model:visible="modalVisible"
    title="Arco Modal 演示"
    @ok="onModalOk"
    @cancel="modalVisible = false"
  >
    <a-space direction="vertical" fill>
      <p>这是 McWeb 后台使用的 Arco Design Vue 弹窗组件。</p>
      <a-space wrap>
        <a-tag color="green"><icon-check-circle /> 成功</a-tag>
        <a-tag color="red"><icon-close-circle /> 危险</a-tag>
        <a-tag color="orangered">警告</a-tag>
      </a-space>
    </a-space>
  </a-modal>
</template>

<style scoped>
.arco-demo-page__header {
  padding: 0;
  margin-bottom: 16px;
}
.arco-demo-page__alert {
  margin-bottom: 16px;
}
.arco-demo-page__stats {
  margin-bottom: 16px;
}
.arco-demo-page__section {
  margin-bottom: 16px;
  border-radius: 4px;
}
.arco-demo-form {
  flex-wrap: wrap;
  gap: 8px 0;
}
</style>
