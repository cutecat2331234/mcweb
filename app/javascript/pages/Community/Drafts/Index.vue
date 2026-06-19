<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Badge from '@/components/ui/Badge.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'
import { confirm } from '@/lib/useConfirm'

defineOptions({ layout: PortalLayout })

const { t } = useI18n()

defineProps<{
  drafts: Array<{
    id: string
    title: string
    body_excerpt: string
    preview_html: string | null
    section_name: string
    section_url: string
    updated_at: string
    scheduled_at: string | null
    has_poll?: boolean
    edit_url: string
  }>
}>()

async function deleteDraft(id: string) {
  const ok = await confirm({
    title: t('forum.drafts.deleteTitle'),
    message: t('forum.drafts.deleteConfirm'),
    confirmLabel: t('forum.drafts.delete'),
    variant: 'destructive',
  })
  if (!ok) return
  router.delete(`/app/forum/drafts/${id}`)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: t('breadcrumb.home'), href: routes.home },
    { label: t('breadcrumb.forum'), href: routes.forum },
    { label: t('forum.drafts.breadcrumb'), current: true },
  ]" />

  <PageHeader :title="t('forum.drafts.title')" :subtitle="t('forum.drafts.subtitle')" />

  <div v-if="drafts.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('forum.drafts.colTitle') }}</TableHead>
          <TableHead>{{ t('forum.drafts.colSection') }}</TableHead>
          <TableHead>{{ t('forum.drafts.colScheduled') }}</TableHead>
          <TableHead>{{ t('forum.drafts.colUpdated') }}</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="draft in drafts" :key="draft.id">
          <TableCell>
            <Link :href="draft.edit_url" class="font-medium hover:underline">{{ draft.title }}</Link>
            <p class="mt-1 text-xs text-muted-foreground">{{ draft.body_excerpt }}</p>
          </TableCell>
          <TableCell>
            <Link :href="draft.section_url" class="hover:underline">{{ draft.section_name }}</Link>
          </TableCell>
          <TableCell>
            {{ draft.scheduled_at || '—' }}
            <Badge v-if="draft.has_poll" variant="secondary" class="ml-1">{{ t('forum.drafts.pollBadge') }}</Badge>
          </TableCell>
          <TableCell>{{ draft.updated_at }}</TableCell>
          <TableCell class="text-right">
            <Button as-child variant="outline" size="sm">
              <Link :href="draft.edit_url">{{ t('forum.drafts.edit') }}</Link>
            </Button>
            <Button type="button" variant="outline" size="sm" class="ml-2" @click="deleteDraft(draft.id)">{{ t('forum.drafts.delete') }}</Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    {{ t('forum.drafts.empty') }}
  </p>
</template>
