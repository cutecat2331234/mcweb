<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
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
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface ApiKey {
  id: number
  name: string
  prefix: string
  scopes: string[]
  user: string | null
  lastUsedAt: string | null
  revoked: boolean
  createdAt: string
  revokeUrl: string
}

defineProps<{
  title: string
  subtitle?: string
  newUrl: string
  keys: ApiKey[]
}>()

async function revoke(key: ApiKey) {
  const ok = await confirm({
    title: t('admin.apiKeys.revokeTitle'),
    message: t('admin.apiKeys.revokeConfirm', { name: key.name }),
    confirmLabel: t('admin.apiKeys.revoke'),
    variant: 'destructive',
  })
  if (!ok) return
  router.post(key.revokeUrl)
}
</script>

<template>
  <PageHeader :title="title" :subtitle="subtitle" />

  <div class="mb-4">
    <Button as-child>
      <Link :href="newUrl">{{ t('admin.apiKeys.new') }}</Link>
    </Button>
  </div>

  <Table>
    <TableHeader>
      <TableRow>
        <TableHead>{{ t('admin.apiKeys.name') }}</TableHead>
        <TableHead>{{ t('admin.apiKeys.prefix') }}</TableHead>
        <TableHead>{{ t('admin.apiKeys.scopes') }}</TableHead>
        <TableHead>{{ t('admin.apiKeys.user') }}</TableHead>
        <TableHead>{{ t('admin.apiKeys.lastUsed') }}</TableHead>
        <TableHead>{{ t('admin.apiKeys.status') }}</TableHead>
        <TableHead></TableHead>
      </TableRow>
    </TableHeader>
    <TableBody>
      <TableRow v-for="key in keys" :key="key.id">
        <TableCell>{{ key.name }}</TableCell>
        <TableCell><code>{{ key.prefix }}…</code></TableCell>
        <TableCell>{{ key.scopes.join(', ') }}</TableCell>
        <TableCell>{{ key.user || '—' }}</TableCell>
        <TableCell>{{ key.lastUsedAt || '—' }}</TableCell>
        <TableCell>{{ key.revoked ? t('admin.apiKeys.revoked') : t('admin.apiKeys.active') }}</TableCell>
        <TableCell>
          <Button v-if="!key.revoked" type="button" variant="destructive" size="sm" @click="revoke(key)">
            {{ t('admin.apiKeys.revoke') }}
          </Button>
        </TableCell>
      </TableRow>
      <TableRow v-if="keys.length === 0">
        <TableCell colspan="7">{{ t('admin.apiKeys.empty') }}</TableCell>
      </TableRow>
    </TableBody>
  </Table>
</template>
