<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: AdminLayout })

export interface Metric {
  label: string
  value: number | string
}

export interface WebhookStatBlock {
  total: number
  success: number
  failed: number
  pending: number
  success_rate: number | null
}

export interface AuditLogItem {
  action: string
  actor: string | null
  created_at: string
}

defineProps<{
  metrics: Metric[]
  webhookStats: {
    forum: WebhookStatBlock
    store: WebhookStatBlock
  }
  webhookFailedLinks: {
    forum: string
    store: string
  }
  recentAuditLogs: AuditLogItem[]
}>()
</script>

<template>
  <PageHeader title="仪表盘" subtitle="系统概览" />

  <div class="mb-8 grid gap-4 md:grid-cols-3">
    <div v-for="metric in metrics" :key="metric.label" class="rounded-lg border p-4">
      <p class="text-sm text-muted-foreground">{{ metric.label }}</p>
      <p class="mt-1 text-2xl font-semibold">{{ metric.value }}</p>
    </div>
  </div>

  <h2 class="mb-3 text-sm font-semibold">Webhook 投递（24 小时）</h2>
  <div class="mb-8 grid gap-4 md:grid-cols-2">
    <div class="rounded-lg border p-4">
      <p class="mb-2 text-sm font-medium">论坛保存搜索</p>
      <p class="text-sm text-muted-foreground">
        共 {{ webhookStats.forum.total }} 次 · 成功 {{ webhookStats.forum.success }} · 失败 {{ webhookStats.forum.failed }} · 进行中 {{ webhookStats.forum.pending }}
      </p>
      <p v-if="webhookStats.forum.success_rate != null" class="mt-1 text-lg font-semibold">
        成功率 {{ webhookStats.forum.success_rate }}%
      </p>
      <Link :href="webhookFailedLinks.forum" class="mt-2 mr-3 inline-block text-sm text-primary hover:underline">查看失败记录</Link>
      <Link :href="adminRoutes.forumWebhookDeliveries" class="mt-2 inline-block text-sm text-muted-foreground hover:underline">全部投递日志</Link>
    </div>
    <div class="rounded-lg border p-4">
      <p class="mb-2 text-sm font-medium">商城订单</p>
      <p class="text-sm text-muted-foreground">
        共 {{ webhookStats.store.total }} 次 · 成功 {{ webhookStats.store.success }} · 失败 {{ webhookStats.store.failed }} · 进行中 {{ webhookStats.store.pending }}
      </p>
      <p v-if="webhookStats.store.success_rate != null" class="mt-1 text-lg font-semibold">
        成功率 {{ webhookStats.store.success_rate }}%
      </p>
      <Link :href="webhookFailedLinks.store" class="mt-2 mr-3 inline-block text-sm text-primary hover:underline">查看失败记录</Link>
      <Link :href="adminRoutes.storeWebhookDeliveries" class="mt-2 inline-block text-sm text-muted-foreground hover:underline">全部投递日志</Link>
    </div>
  </div>

  <h2 class="mb-3 text-sm font-semibold">最近审计日志</h2>
  <div v-if="recentAuditLogs.length" class="mb-8 rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>操作</TableHead>
          <TableHead>操作者</TableHead>
          <TableHead>时间</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="(log, index) in recentAuditLogs" :key="index">
          <TableCell>{{ log.action }}</TableCell>
          <TableCell>{{ log.actor || '—' }}</TableCell>
          <TableCell>{{ log.created_at }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="mb-8 text-sm text-muted-foreground">暂无审计日志。</p>

  <h2 class="mb-3 text-sm font-semibold">快捷链接</h2>
  <div class="flex flex-wrap gap-3">
    <Link :href="adminRoutes.forumSections" class="text-sm hover:underline">论坛板块</Link>
    <Link :href="adminRoutes.storeProducts" class="text-sm hover:underline">商城商品</Link>
    <Link :href="adminRoutes.site" class="text-sm hover:underline">查看站点</Link>
  </div>
</template>
