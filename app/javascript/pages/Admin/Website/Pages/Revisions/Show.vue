<script setup lang="ts">
import { Link, router } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  title: string
  page: { id: string; title: string }
  revision: { id: number; revision_number: number; author: string | null; created_at: string; snapshot: Record<string, unknown>; restoreUrl: string }
  backUrl: string
}>()

function restoreDraft() {
  router.post(props.revision.restoreUrl)
}
</script>

<template>
  <PageHeader :title="title" :subtitle="`#${revision.revision_number}`" />
  <pre class="max-w-4xl overflow-auto rounded-lg border bg-muted p-4 text-xs">{{ JSON.stringify(revision.snapshot, null, 2) }}</pre>
  <div class="mt-4 flex gap-2">
    <Button type="button" @click="restoreDraft">Restore as draft</Button>
    <Button as-child variant="outline"><Link :href="backUrl">Back</Link></Button>
  </div>
</template>
