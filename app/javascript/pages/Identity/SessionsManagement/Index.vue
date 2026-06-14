<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Badge from '@/components/ui/Badge.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: PortalLayout })

defineProps<{
  sessions: Array<{
    id: number
    ip_address: string | null
    user_agent: string | null
    last_active_at: string | null
    current: boolean
  }>
}>()

function revokeSession(id: number) {
  router.delete(`/identity/sessions/${id}`)
}
</script>

<template>
  <PageHeader title="活跃会话" subtitle="管理你的登录设备" />

  <div class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>IP</TableHead>
          <TableHead>设备</TableHead>
          <TableHead>最后活跃</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="session in sessions" :key="session.id">
          <TableCell>{{ session.ip_address || '—' }}</TableCell>
          <TableCell class="max-w-xs truncate">{{ session.user_agent || '—' }}</TableCell>
          <TableCell>
            {{ session.last_active_at || '—' }}
            <Badge v-if="session.current" class="ml-2" variant="success">当前</Badge>
          </TableCell>
          <TableCell>
            <Button v-if="!session.current" variant="ghost" size="sm" type="button" @click="revokeSession(session.id)">
              撤销
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
</template>
