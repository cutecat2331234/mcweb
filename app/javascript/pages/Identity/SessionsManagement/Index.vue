<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
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

const { t } = useI18n()

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
  router.delete(`/app/identity/sessions/${id}`)
}
</script>

<template>
  <PageHeader :title="t('identity.sessions.title')" :subtitle="t('identity.sessions.subtitle')" />

  <div class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('identity.sessions.colIp') }}</TableHead>
          <TableHead>{{ t('identity.sessions.colDevice') }}</TableHead>
          <TableHead>{{ t('identity.sessions.colLastActive') }}</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="session in sessions" :key="session.id">
          <TableCell>{{ session.ip_address || '—' }}</TableCell>
          <TableCell class="max-w-xs truncate">{{ session.user_agent || '—' }}</TableCell>
          <TableCell>
            {{ session.last_active_at || '—' }}
            <Badge v-if="session.current" class="ml-2" variant="success">{{ t('identity.sessions.current') }}</Badge>
          </TableCell>
          <TableCell>
            <Button v-if="!session.current" variant="ghost" size="sm" type="button" @click="revokeSession(session.id)">
              {{ t('identity.sessions.revoke') }}
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
</template>
