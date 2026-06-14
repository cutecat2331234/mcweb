<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

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
    edit_url: string
  }>
}>()

function deleteDraft(id: string) {
  if (!confirm('确定删除此草稿？')) return
  router.delete(`/forum/drafts/${id}`)
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: '我的草稿', current: true },
  ]" />

  <PageHeader title="我的草稿" subtitle="未发布的主题草稿" />

  <div v-if="drafts.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>标题 / 预览</TableHead>
          <TableHead>分区</TableHead>
          <TableHead>定时</TableHead>
          <TableHead>更新时间</TableHead>
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
          <TableCell>{{ draft.scheduled_at || '—' }}</TableCell>
          <TableCell>{{ draft.updated_at }}</TableCell>
          <TableCell class="text-right">
            <Button as-child variant="outline" size="sm">
              <Link :href="draft.edit_url">编辑</Link>
            </Button>
            <Button type="button" variant="outline" size="sm" class="ml-2" @click="deleteDraft(draft.id)">删除</Button>
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无草稿。在新建主题时可保存草稿。
  </p>
</template>
