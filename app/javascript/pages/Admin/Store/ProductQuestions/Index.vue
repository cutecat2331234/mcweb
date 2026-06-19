<script setup lang="ts">
import { router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

defineProps<{
  questions: Array<{
    id: number
    product: string
    author: string
    body: string
    status: string
    created_at: string
    order_number?: string | null
    hide_url: string
    unhide_url: string
  }>
}>()

function hideQuestion(url: string) {
  router.patch(url)
}

function unhideQuestion(url: string) {
  router.patch(url)
}
</script>

<template>
  <PageHeader :title="t('admin.productQuestions.title')" />

  <div v-if="questions.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{{ t('admin.productQuestions.colProduct') }}</TableHead>
          <TableHead>{{ t('admin.productQuestions.colAuthor') }}</TableHead>
          <TableHead>{{ t('admin.productQuestions.colQuestion') }}</TableHead>
          <TableHead>{{ t('admin.productQuestions.colOrder') }}</TableHead>
          <TableHead>{{ t('admin.productQuestions.colStatus') }}</TableHead>
          <TableHead>{{ t('admin.common.time') }}</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="q in questions" :key="q.id">
          <TableCell>{{ q.product }}</TableCell>
          <TableCell>{{ q.author }}</TableCell>
          <TableCell class="max-w-xs truncate">{{ q.body }}</TableCell>
          <TableCell>{{ q.order_number || '—' }}</TableCell>
          <TableCell>{{ q.status }}</TableCell>
          <TableCell>{{ q.created_at }}</TableCell>
          <TableCell class="flex gap-2">
            <Button v-if="q.status === 'published'" type="button" size="sm" variant="outline" @click="hideQuestion(q.hide_url)">
              {{ t('admin.common.hide') }}
            </Button>
            <Button v-else type="button" size="sm" variant="outline" @click="unhideQuestion(q.unhide_url)">
              {{ t('admin.common.restore') }}
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">{{ t('admin.productQuestions.empty') }}</p>
</template>
