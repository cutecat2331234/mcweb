<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

defineProps<{
  metrics: Array<{ label: string; value: number | string }>
  topPosters: Array<{ username: string; posts_count: number }>
  newestMembers: Array<{ username: string; joined_at: string }>
}>()
</script>

<template>
  <PageHeader :title="t('admin.forumStatsPage.title')" :subtitle="t('admin.forumStatsPage.subtitle')" />

  <div class="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
    <div v-for="metric in metrics" :key="metric.label" class="rounded-lg border p-4">
      <p class="text-sm text-muted-foreground">{{ metric.label }}</p>
      <p class="mt-1 text-2xl font-semibold">{{ metric.value }}</p>
    </div>
  </div>

  <div class="grid gap-8 lg:grid-cols-2">
    <div>
      <h2 class="mb-3 text-sm font-semibold">{{ t('admin.forumStatsPage.topPosters') }}</h2>
      <div v-if="topPosters.length" class="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{{ t('admin.forumStatsPage.colMember') }}</TableHead>
              <TableHead>{{ t('admin.forumStatsPage.colPosts') }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="poster in topPosters" :key="poster.username">
              <TableCell>@{{ poster.username }}</TableCell>
              <TableCell>{{ poster.posts_count }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
      <p v-else class="text-sm text-muted-foreground">{{ t('admin.forumStatsPage.empty') }}</p>
    </div>

    <div>
      <h2 class="mb-3 text-sm font-semibold">{{ t('admin.forumStatsPage.newestMembers') }}</h2>
      <div v-if="newestMembers.length" class="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{{ t('admin.forumStatsPage.colMember') }}</TableHead>
              <TableHead>{{ t('admin.forumStatsPage.colJoined') }}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            <TableRow v-for="member in newestMembers" :key="member.username">
              <TableCell>@{{ member.username }}</TableCell>
              <TableCell>{{ member.joined_at }}</TableCell>
            </TableRow>
          </TableBody>
        </Table>
      </div>
      <p v-else class="text-sm text-muted-foreground">{{ t('admin.forumStatsPage.empty') }}</p>
    </div>
  </div>
</template>
