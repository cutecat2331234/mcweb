<script setup lang="ts">
import { ref } from 'vue'
import { router } from '@inertiajs/vue3'
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

const locations = ['header', 'footer'] as const

const draft = ref({
  label: '',
  url: '',
  website_page_id: '',
  location: 'header',
  visible: true,
})

function itemsForLocation(location: string) {
  return props.items.filter((item) => item.location === location)
}

function createItem() {
  router.post(props.submitUrl, {
    nav_item: {
      ...draft.value,
      website_page_id: draft.value.website_page_id || null,
      url: draft.value.url || null,
    },
  })
}

function removeItem(id: number) {
  router.delete(`${props.submitUrl}/${id}`)
}

function moveItem(location: string, index: number, direction: -1 | 1) {
  const group = itemsForLocation(location)
  const next = index + direction
  if (next < 0 || next >= group.length) return
  const ids = group.map((item) => item.id)
  ;[ids[index], ids[next]] = [ids[next], ids[index]]
  router.patch(props.reorderUrl, { item_ids: ids, location }, { preserveScroll: true })
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="mb-8 max-w-lg space-y-3 rounded-lg border p-4" @submit.prevent="createItem">
    <h2 class="text-sm font-semibold">{{ t('admin.website.nav.add', 'Add item') }}</h2>
    <div class="space-y-2"><Label>Label</Label><Input v-model="draft.label" required /></div>
    <div class="space-y-2">
      <Label>Page</Label>
      <select v-model="draft.website_page_id" class="w-full rounded-md border bg-background px-3 py-2 text-sm">
        <option value="">— external URL —</option>
        <option v-for="page in pages" :key="page.id" :value="page.id">{{ page.title }} (/{{ page.slug }})</option>
      </select>
    </div>
    <div v-if="!draft.website_page_id" class="space-y-2"><Label>URL</Label><Input v-model="draft.url" placeholder="/blog" /></div>
    <div class="space-y-2">
      <Label>Location</Label>
      <select v-model="draft.location" class="w-full rounded-md border bg-background px-3 py-2 text-sm">
        <option v-for="location in locations" :key="location" :value="location">{{ location }}</option>
      </select>
    </div>
    <label class="flex items-center gap-2 text-sm"><Checkbox v-model="draft.visible" /> Visible</label>
    <Button type="submit">{{ t('admin.ui.save') }}</Button>
  </form>

  <div v-for="location in locations" :key="location" class="mb-8 max-w-2xl">
    <h2 class="mb-2 text-sm font-semibold capitalize">{{ location }}</h2>
    <ul class="space-y-2">
      <li
        v-for="(item, index) in itemsForLocation(location)"
        :key="item.id"
        class="flex items-center gap-2 rounded-lg border p-3 text-sm"
      >
        <span class="font-medium">{{ item.label }}</span>
        <span class="text-muted-foreground">{{ item.href }}</span>
        <div class="ml-auto flex gap-1">
          <Button type="button" size="sm" variant="outline" :disabled="index === 0" @click="moveItem(location, index, -1)">↑</Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            :disabled="index === itemsForLocation(location).length - 1"
            @click="moveItem(location, index, 1)"
          >↓</Button>
          <Button type="button" size="sm" variant="destructive" @click="removeItem(item.id)">{{ t('admin.ui.delete') }}</Button>
        </div>
      </li>
    </ul>
  </div>
</template>
