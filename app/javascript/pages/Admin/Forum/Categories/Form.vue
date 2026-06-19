<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  category: { id?: number; name: string; slug: string; position: number; color_hex?: string; icon?: string; description?: string; seo_title?: string; seo_description?: string }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ category: { ...props.category } })

function submit() {
  if (props.method === 'patch') {
    form.patch(props.submitUrl)
  } else {
    form.post(props.submitUrl)
  }
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('admin.common.name') }}</Label>
      <Input id="name" v-model="form.category.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.common.slugFull') }}</Label>
      <Input id="slug" v-model="form.category.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="position">{{ t('admin.common.position') }}</Label>
      <Input id="position" v-model.number="form.category.position" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="color_hex">{{ t('admin.forms.forumCategory.colorHex') }}</Label>
      <Input id="color_hex" v-model="form.category.color_hex" placeholder="#2563eb" />
    </div>
    <div class="space-y-2">
      <Label for="icon">{{ t('admin.forms.forumCategory.iconEmoji') }}</Label>
      <Input id="icon" v-model="form.category.icon" placeholder="💬" />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.common.description') }}</Label>
      <Textarea id="description" v-model="form.category.description" rows="3" :placeholder="t('admin.forms.forumCategory.descriptionPlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label for="seo_title">{{ t('admin.forms.category.seoTitle') }}</Label>
      <Input id="seo_title" v-model="form.category.seo_title" />
    </div>
    <div class="space-y-2">
      <Label for="seo_description">{{ t('admin.forms.category.seoDescription') }}</Label>
      <Textarea id="seo_description" v-model="form.category.seo_description" rows="2" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
