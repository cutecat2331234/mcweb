<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import Button from '@/components/ui/Button.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface Subscription {
  id: number
  name: string
  url: string
  event: string
  active: boolean
  lastStatus: string | null
  lastDeliveredAt: string | null
  failureCount: number
  editUrl: string
}

defineProps<{
  title: string
  subtitle?: string
  newUrl: string
  subscriptions: Subscription[]
}>()
</script>

<template>
  <PageHeader :title="title" :subtitle="subtitle" />

  <div class="mb-4">
    <Button as-child>
      <Link :href="newUrl">{{ t('admin.webhookSubscriptions.new') }}</Link>
    </Button>
  </div>

  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>{{ t('admin.webhookSubscriptions.name') }}</TableHead>
        <TableHead>{{ t('admin.webhookSubscriptions.event') }}</TableHead>
        <TableHead>{{ t('admin.webhookSubscriptions.url') }}</TableHead>
        <TableHead>{{ t('admin.webhookSubscriptions.status') }}</TableHead>
        <TableHead>{{ t('admin.webhookSubscriptions.lastDelivered') }}</TableHead>
        <TableHead></TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      <TableRow v-for="s in subscriptions" :key="s.id">
        <TableCell>{{ s.name }}</TableCell>
        <TableCell><code>{{ s.event }}</code></TableCell>
        <TableCell class="max-w-xs truncate">{{ s.url }}</TableCell>
        <TableCell>
          <span>{{ s.active ? t('admin.webhookSubscriptions.active') : t('admin.webhookSubscriptions.disabled') }}</span>
          <span v-if="s.lastStatus"> · {{ s.lastStatus }}</span>
          <span v-if="s.failureCount > 0"> · ✗{{ s.failureCount }}</span>
        </TableCell>
        <TableCell>{{ s.lastDeliveredAt || '—' }}</TableCell>
        <TableCell>
          <Button as-child variant="outline" size="sm">
            <Link :href="s.editUrl">{{ t('admin.ui.edit') }}</Link>
          </Button>
        </TableCell>
      </TableRow>
      <TableRow v-if="subscriptions.length === 0">
        <TableCell colspan="6">{{ t('admin.webhookSubscriptions.empty') }}</TableCell>
      </TableRow>
    </TableBody>
  </Table>
</template>
