<script setup lang="ts">
import { useForm, Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

interface PointSettingItem {
  key: string
  value: string
  label: string
  hint?: string | null
}

const props = defineProps<{
  settings: PointSettingItem[]
  save_url: string
  back_url: string
}>()

const form = useForm<{ settings: Record<string, string> }>({
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

function submit() {
  form.transform((data) => ({ settings: data.settings })).patch(props.save_url, {
    preserveScroll: true,
  })
}
</script>

<template>
  <div class="mb-4 flex items-center justify-between">
    <PageHeader :title="t('admin.forum.points.settingsTitle')" :subtitle="t('admin.forum.points.settingsSubtitle')" />
    <Link :href="back_url" class="rounded-md border px-3 py-1.5 text-sm no-underline hover:bg-muted">
      {{ t('admin.forum.points.backToLog') }}
    </Link>
  </div>

  <form class="max-w-xl space-y-5" @submit.prevent="submit">
    <div v-for="item in settings" :key="item.key" class="space-y-1.5">
      <Label :for="item.key">{{ item.label }}</Label>
      <Input
        :id="item.key"
        v-model="form.settings[item.key]"
        type="number"
        min="0"
        step="1"
        class="w-40"
      />
      <p v-if="item.hint" class="text-xs text-muted-foreground">{{ item.hint }}</p>
    </div>

    <div class="flex items-center gap-3 pt-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.common.saveSettings') }}</Button>
      <span v-if="form.recentlySuccessful" class="text-sm text-emerald-600">{{ t('admin.common.saved') }}</span>
    </div>
  </form>
</template>
