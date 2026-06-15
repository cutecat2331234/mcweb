<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

export interface StoreSettingItem {
  key: string
  value: string
  label: string
  hint?: string | null
  input_type: 'text' | 'number'
}

const props = defineProps<{
  settings: StoreSettingItem[]
}>()

const form = useForm({
  settings: Object.fromEntries(props.settings.map((s) => [s.key, s.value])),
})

function submit() {
  form.patch(adminRoutes.storeSettings)
}
</script>

<template>
  <PageHeader title="商城设置" subtitle="运费、购物车、对比、SEO 与订单策略（对标 XenForo 资源管理 / WooCommerce 商店选项）" />

  <form class="max-w-xl space-y-4" @submit.prevent="submit">
    <div v-for="setting in settings" :key="setting.key" class="rounded-lg border p-4 space-y-2">
      <Label :for="setting.key" class="text-sm font-medium">{{ setting.label }}</Label>
      <p v-if="setting.hint" class="text-xs text-muted-foreground">{{ setting.hint }}</p>
      <Input
        :id="setting.key"
        v-model="form.settings[setting.key]"
        :type="setting.input_type === 'number' ? 'number' : 'text'"
        :min="setting.input_type === 'number' ? 0 : undefined"
      />
    </div>
    <Button type="submit" :disabled="form.processing">保存商城设置</Button>
  </form>
</template>
