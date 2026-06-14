<script setup lang="ts">
import { router } from '@inertiajs/vue3'
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

defineProps<{
  questions: Array<{
    id: number
    product: string
    author: string
    body: string
    status: string
    created_at: string
    hide_url: string
  }>
}>()

function hideQuestion(url: string) {
  router.patch(url)
}
</script>

<template>
  <PageHeader title="商品问答" />

  <div v-if="questions.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>商品</TableHead>
          <TableHead>提问者</TableHead>
          <TableHead>问题</TableHead>
          <TableHead>状态</TableHead>
          <TableHead>时间</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="q in questions" :key="q.id">
          <TableCell>{{ q.product }}</TableCell>
          <TableCell>{{ q.author }}</TableCell>
          <TableCell class="max-w-xs truncate">{{ q.body }}</TableCell>
          <TableCell>{{ q.status }}</TableCell>
          <TableCell>{{ q.created_at }}</TableCell>
          <TableCell>
            <Button v-if="q.status === 'published'" type="button" size="sm" variant="outline" @click="hideQuestion(q.hide_url)">
              隐藏
            </Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>
  <p v-else class="text-sm text-muted-foreground">暂无问答。</p>
</template>
