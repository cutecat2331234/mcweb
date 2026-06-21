<script setup lang="ts">
import { ref } from 'vue'
import { Link, router } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface NavItem {
  id: number
  label: string
  url: string | null
  website_page_id: number | null
  page_public_id: string | null
  location: string
  visible: boolean
  position: number
  href: string
}

const props = defineProps<{
  title: string
  items: NavItem[]
  pages: Array<{ id: string; title: string; slug: string }>
  submitUrl: string
  reorderUrl: string
}>()

const form = ref({
  label: '',
  url: '',
  website_page_id: '',
  location: 'header',
  visible: true,
})

function createItem() {
  router.post(props.submitUrl, {
    nav_item: {
      ...form.value,
      website_page_id: form.value.website_page_id || null,
      url: form.value.url || null,
    },
  })
}

function removeItem(id: number) {
  router.delete(`${props.submitUrl}/${id}`)
}

function moveItem(index: number, direction: -1 | 1) {
  const next = index + direction
  if (next < 0 || next >= props.items.length) return
  const ids = props.items.map((i) => i.id)
  ;[ids[index], ids[next]] = [ids[next], ids[index]]
  router.patch(props.reorderUrl, { item_ids: ids }, { preserveScroll: true })
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="mb-8 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="createItem">
    <h2 class="text-sm font-semibold">{{ t('admin.website.nav.add', 'Add item') }}</h2>
    <div class="space-y-2"><Label>Label</Label><Input v-model="form.label" required /></div>
    <div class="space-y-2">
      <Label>Page</Label>
      <select v-model="form.website_page_id" class="w-full rounded-md border bg-background px-3 py-2 text-sm">
        <option value="">— external URL —</option>
        <option v-for="page in pages" :key="page.id" :value="page.id">{{ page.title }} (/{{ page.slug }})</option>
      </select>
    </div>
    <div v-if="!form.website_page_id" class="space-y-2"><Label>URL</Label><Input v-model="form.url" placeholder="/blog" /></div>
    <div class="space-y-2">
      <Label>Location</Label>
      <select v-model="form.location" class="w-full rounded-md border bg-background px-3 py-2 text-sm">
        <option value="header">header</option>
        <option value="footer">footer</option>
      </select>
    </div>
    <label class="flex items-center gap-2 text-sm"><Checkbox v-model="form.visible" /> Visible</label>
    <Button type="submit">{{ t('admin.ui.save') }}</Button>
  </form>

  <ul class="max-w-2xl space-y-2">
    <li v-for="(item, index) in items" :key="item.id" class="flex items-center gap-2 rounded-lg border p-3 text-sm">
      <span class="font-medium">{{ item.label }}</span>
      <span class="text-muted-foreground">{{ item.href }}</span>
      <span class="text-xs text-muted-foreground">({{ item.location }})</span>
      <div class="ml-auto flex gap-1">
        <Button type="button" size="sm" variant="outline" :disabled="index === 0" @click="moveItem(index, -1)">↑</Button>
        <Button type="button" size="sm" variant="outline" :disabled="index === items.length - 1" @click="moveItem(index, 1)">↓</Button>
        <Button type="button" size="sm" variant="destructive" @click="removeItem(item.id)">{{ t('admin.ui.delete') }}</Button>
      </div>
    </li>
  </ul>
</template>
