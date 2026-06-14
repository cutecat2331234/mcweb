<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import WebsiteLayout from '@/layouts/WebsiteLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Table from '@/components/ui/Table.vue'
import TableBody from '@/components/ui/TableBody.vue'
import TableCell from '@/components/ui/TableCell.vue'
import TableHead from '@/components/ui/TableHead.vue'
import TableHeader from '@/components/ui/TableHeader.vue'
import TableRow from '@/components/ui/TableRow.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: WebsiteLayout })

defineProps<{
  articles: Array<{
    title: string
    article_type: string
    published_at: string | null
    url: string
  }>
}>()
</script>

<template>
  <section class="mx-auto max-w-5xl px-4 py-16">
    <PageHeader title="新闻与公告" />

    <div v-if="articles.length" class="rounded-lg border border-white/10 bg-white/5">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>标题</TableHead>
            <TableHead>类型</TableHead>
            <TableHead>发布时间</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          <TableRow v-for="article in articles" :key="article.url">
            <TableCell><Link :href="article.url" class="font-medium hover:underline">{{ article.title }}</Link></TableCell>
            <TableCell>{{ article.article_type }}</TableCell>
            <TableCell>{{ article.published_at || '—' }}</TableCell>
          </TableRow>
        </TableBody>
      </Table>
    </div>
    <p v-else class="text-slate-300">暂无已发布文章。</p>
  </section>
</template>
