<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'

defineOptions({ layout: AdminLayout })

defineProps<{
  title: string
  page: { id: string; title: string }
  revisions: Array<{ id: number; revision_number: number; author: string | null; created_at: string; url: string }>
  backUrl: string
}>()
</script>

<template>
  <PageHeader :title="title" :subtitle="page.title" />
  <ul class="max-w-2xl space-y-2">
    <li v-for="rev in revisions" :key="rev.id" class="flex items-center justify-between rounded-lg border p-3 text-sm">
      <span>#{{ rev.revision_number }} · {{ rev.author || '—' }} · {{ rev.created_at }}</span>
      <Button as-child size="sm" variant="outline"><Link :href="rev.url">View</Link></Button>
    </li>
  </ul>
  <Button as-child class="mt-4" variant="outline"><Link :href="backUrl">Back</Link></Button>
</template>
