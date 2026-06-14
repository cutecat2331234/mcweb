<script setup lang="ts">
import { Link } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Card from '@/components/ui/Card.vue'
import CardContent from '@/components/ui/CardContent.vue'

defineOptions({ layout: AdminLayout })

export interface DetailField {
  label: string
  value: string
}

export interface DetailSection {
  title: string
  items: Array<{ label: string; value?: string }>
}

export interface DetailAction {
  label: string
  href: string
  method?: 'get' | 'post' | 'patch' | 'delete'
  confirm?: string
  variant?: 'default' | 'outline'
  data?: Record<string, unknown>
}

defineProps<{
  title: string
  subtitle?: string
  fields: DetailField[]
  sections?: DetailSection[]
  preformatted?: { title: string; content: string }
  actions?: DetailAction[]
  backUrl: string
}>()
</script>

<template>
  <PageHeader :title="title" :subtitle="subtitle" />

  <Card class="max-w-3xl">
    <CardContent class="space-y-3 pt-6">
      <div v-for="field in fields" :key="field.label" class="flex justify-between gap-4 text-sm">
        <span class="text-muted-foreground">{{ field.label }}</span>
        <span class="text-right font-medium">{{ field.value }}</span>
      </div>
    </CardContent>
  </Card>

  <div v-for="section in sections" :key="section.title" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ section.title }}</h2>
    <ul class="space-y-2 rounded-lg border p-4 text-sm">
      <li v-for="(item, index) in section.items" :key="index">
        <code v-if="item.label" class="text-xs text-muted-foreground">{{ item.label }}</code>
        <span v-if="item.value"> — {{ item.value }}</span>
      </li>
    </ul>
  </div>

  <div v-if="preformatted" class="mt-6 max-w-3xl">
    <h2 class="mb-3 text-sm font-semibold">{{ preformatted.title }}</h2>
    <pre class="overflow-auto rounded-lg border bg-muted p-4 text-xs">{{ preformatted.content }}</pre>
  </div>

  <div class="mt-6 flex flex-wrap gap-3">
    <template v-for="action in actions" :key="action.href + action.label">
      <Button
        v-if="action.method && action.method !== 'get'"
        as-child
        :variant="action.variant ?? 'default'"
      >
        <Link
          :href="action.href"
          :method="action.method"
          as="button"
          :data="action.data"
        >
          {{ action.label }}
        </Link>
      </Button>
      <Button v-else as-child :variant="action.variant ?? 'outline'">
        <Link :href="action.href">{{ action.label }}</Link>
      </Button>
    </template>
    <Button as-child variant="outline">
      <Link :href="backUrl">返回</Link>
    </Button>
  </div>
</template>
