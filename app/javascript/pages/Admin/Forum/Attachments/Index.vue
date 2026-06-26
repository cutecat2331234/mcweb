<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { adminRoutes } from '@/lib/adminRoutes'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

type Attachment = {
  id: number
  filename: string
  size: string
  content_type: string | null
  downloads: number
  uploader: string | null
  linked: boolean
  post_url: string | null
  created_at: string
  delete_url: string
}

const props = defineProps<{
  attachments: Attachment[]
  pagination: PaginationMeta
  filter: string
  orphanCount: number
  pruneUrl: string
}>()

function setFilter(value: string) {
  router.get(adminRoutes.forumAttachments, value ? { filter: value } : {}, { preserveState: true })
}

async function removeAttachment(a: Attachment) {
  const ok = await confirm({
    title: t('admin.attachments.deleteTitle'),
    message: t('admin.attachments.deleteConfirm', { name: a.filename }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(a.delete_url, { preserveScroll: true })
}

async function prune() {
  const ok = await confirm({
    title: t('admin.attachments.pruneTitle'),
    message: t('admin.attachments.pruneConfirm', { count: props.orphanCount }),
    confirmLabel: t('admin.ui.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(props.pruneUrl)
}
</script>

<template>
  <div class="mb-4 flex items-center justify-between">
    <PageHeader :title="t('admin.attachments.title')" :subtitle="t('admin.attachments.subtitle')" />
    <Button v-if="orphanCount > 0" type="button" variant="destructive" size="sm" @click="prune">
      {{ t('admin.attachments.prune', { count: orphanCount }) }}
    </Button>
  </div>

  <div class="mb-4 flex gap-2">
    <button
      type="button"
      class="rounded-md border px-3 py-1.5 text-sm no-underline"
      :class="!filter ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-muted'"
      @click="setFilter('')"
    >{{ t('admin.attachments.tabAll') }}</button>
    <button
      type="button"
      class="rounded-md border px-3 py-1.5 text-sm no-underline"
      :class="filter === 'orphans' ? 'border-primary bg-primary text-primary-foreground' : 'hover:bg-muted'"
      @click="setFilter('orphans')"
    >{{ t('admin.attachments.tabOrphans') }} ({{ orphanCount }})</button>
  </div>

  <div v-if="attachments.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('admin.attachments.colFile') }}</TableHead>
          <TableHead>{{ t('admin.attachments.colSize') }}</TableHead>
          <TableHead>{{ t('admin.attachments.colUploader') }}</TableHead>
          <TableHead>{{ t('admin.attachments.colDownloads') }}</TableHead>
          <TableHead>{{ t('admin.attachments.colLinked') }}</TableHead>
          <TableHead></TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="a in attachments" :key="a.id">
          <TableCell class="font-medium">{{ a.filename }}</TableCell>
          <TableCell>{{ a.size }}</TableCell>
          <TableCell>{{ a.uploader ? '@' + a.uploader : '—' }}</TableCell>
          <TableCell>{{ a.downloads }}</TableCell>
          <TableCell>
            <Link v-if="a.linked && a.post_url" :href="a.post_url" class="text-primary hover:underline">{{ t('admin.attachments.linked') }}</Link>
            <span v-else class="text-amber-600">{{ t('admin.attachments.orphan') }}</span>
          </TableCell>
          <TableCell>
            <button type="button" class="text-xs text-destructive hover:underline" @click="removeAttachment(a)">{{ t('admin.ui.delete') }}</button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">{{ t('admin.attachments.empty') }}</p>

  <Pagination :pagination="pagination" :base-path="adminRoutes.forumAttachments" />
</template>
