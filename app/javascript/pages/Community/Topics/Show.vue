<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
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
import Textarea from '@/components/ui/Textarea.vue'
import { routes } from '@/lib/routes'

defineOptions({ layout: PortalLayout })

export interface PostItem {
  id: number
  floor_number: number
  author: string
  body: string
  created_at: string
}

const props = defineProps<{
  topic: {
    id: string
    title: string
    author: string | null
    locked: boolean
    section: { name: string; slug: string; url: string }
  }
  posts: PostItem[]
  canReply: boolean
}>()

const form = useForm({
  post: {
    topic_id: props.topic.id,
    body: '',
  },
})

function submitReply() {
  form.post('/forum/posts', {
    preserveScroll: true,
    onSuccess: () => { form.post.body = '' },
  })
}
</script>

<template>
  <Breadcrumb :items="[
    { label: '首页', href: routes.home },
    { label: '论坛', href: routes.forum },
    { label: topic.section.name, href: topic.section.url },
    { label: topic.title, current: true },
  ]" />

  <PageHeader :title="topic.title" :subtitle="topic.author ? `作者 ${topic.author}` : undefined" />

  <p v-if="topic.locked" class="mb-4 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900 dark:bg-amber-950 dark:text-amber-100">
    此主题已锁定，无法回复。
  </p>

  <div class="rounded-lg border">
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead class="w-16">#</TableHead>
          <TableHead>作者</TableHead>
          <TableHead>内容</TableHead>
          <TableHead>时间</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        <TableRow v-for="post in posts" :key="post.id">
          <TableCell>{{ post.floor_number }}</TableCell>
          <TableCell>{{ post.author }}</TableCell>
          <TableCell class="whitespace-pre-wrap">{{ post.body }}</TableCell>
          <TableCell>{{ post.created_at }}</TableCell>
        </TableRow>
      </TableBody>
    </Table>
  </div>

  <section v-if="canReply" class="mt-8 max-w-2xl">
    <h2 class="mb-3 text-sm font-semibold">回复</h2>
    <form class="space-y-3" @submit.prevent="submitReply">
      <Textarea v-model="form.post.body" required rows="6" />
      <Button type="submit" :disabled="form.processing">发表回复</Button>
    </form>
  </section>
</template>
