<script setup lang="ts">
import { computed } from 'vue'
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  tag: { id?: number; name: string; slug: string; description: string; staff_only: boolean; color_hex: string; canonical_tag_id?: number | null }
  canonicalTags?: Array<{ id: number; name: string }>
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ tag: { ...props.tag } })

const canonicalTagOptions = computed(() => [
  { value: '', label: t('admin.forms.tag.canonicalNone') },
  ...(props.canonicalTags || []).map((tag) => ({ value: String(tag.id), label: tag.name })),
])

function updateCanonicalTagId(value: string) {
  form.tag.canonical_tag_id = value ? Number(value) : null
}

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('admin.common.name') }}</Label>
      <Input id="name" v-model="form.tag.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.forms.tag.slug') }}</Label>
      <Input id="slug" v-model="form.tag.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.common.description') }}</Label>
      <Textarea id="description" v-model="form.tag.description" rows="3" />
    </div>
    <div class="space-y-2">
      <Label for="color_hex">{{ t('admin.common.colorHex') }}</Label>
      <Input id="color_hex" v-model="form.tag.color_hex" placeholder="#22c55e" />
    </div>
    <div v-if="canonicalTags?.length" class="space-y-2">
      <Label for="canonical_tag_id">{{ t('admin.forms.tag.canonicalLabel') }}</Label>
      <Select
        id="canonical_tag_id"
        :model-value="form.tag.canonical_tag_id == null ? '' : String(form.tag.canonical_tag_id)"
        :options="canonicalTagOptions"
        block
        @update:model-value="updateCanonicalTagId"
      />
      <p class="text-xs text-muted-foreground">{{ t('admin.forms.tag.canonicalHint') }}</p>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.tag.staff_only" />
      {{ t('admin.forms.tag.staffOnly') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline"><Link :href="backUrl">{{ t('admin.ui.back') }}</Link></Button>
    </div>
  </form>
</template>
