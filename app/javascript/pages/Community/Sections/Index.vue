<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import PortalLayout from '@/layouts/PortalLayout.vue'
import Breadcrumb from '@/components/portal/Breadcrumb.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Pagination, { type PaginationMeta } from '@/components/portal/Pagination.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface SectionItem {
  id: number
  name: string
  slug: string
  description: string | null
  category_name: string | null
  url: string
}

defineProps<{
  sections: SectionItem[]
  pagination: PaginationMeta
}>()
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', current: true },
  ]" />

  <PageHeader title="论坛板块" subtitle="浏览社区讨论分区" />

  <div v-if="sections.length" class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>板块</TableHead>
          <TableHead>分类</TableHead>
          <TableHead>简介</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="section in sections" :key="section.id">
          <TableCell>
            <Link :href="section.url" class="font-medium hover:underline">
              {{ section.name }}
            </Link>
            <span class="ml-2 text-xs text-muted-foreground">{{ section.slug }}</span>
          </TableCell>
          <TableCell>{{ section.category_name || '—' }}</TableCell>
          <TableCell class="text-muted-foreground">
            {{ section.description || '—' }}
          </TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <p v-else class="rounded-lg border border-dashed p-8 text-center text-sm text-muted-foreground">
    暂无论坛板块。
  </p>

  <Pagination :pagination="pagination" :base-path="routes.forum" />
</template>
