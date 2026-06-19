<script setup lang="ts">
import { computed, ref } from 'vue'
import { useForm } from '@inertiajs/vue3'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Checkbox from '@/components/ui/Checkbox.vue'
import Alert from '@/components/ui/Alert.vue'
import { adminRoutes } from '@/lib/adminRoutes'

defineOptions({ layout: AdminLayout })

export interface FeatureToggleItem {
  id: string
  label: string
  description: string
  enabled: boolean
}

const props = defineProps<{
  features: FeatureToggleItem[]
}>()

const form = useForm({
  features: Object.fromEntries(props.features.map((feature) => [feature.id, feature.enabled])),
})

const localError = ref('')

const portalBothDisabled = computed(() => !form.features.forum && !form.features.store)

function submit() {
  localError.value = ''
  if (portalBothDisabled.value) {
    localError.value = '论坛和商城至少需要保留一个开启。'
    return
  }
  form.patch(adminRoutes.featureToggles)
}
</script>

<template>
  <PageHeader
    title="功能开关"
    subtitle="关闭后前台对应入口会自动隐藏；侧栏仅保留一个模块时按钮会占满整行。"
  />

  <Alert v-if="localError" variant="destructive" class="mb-4 max-w-2xl">
    {{ localError }}
  </Alert>

  <form class="max-w-2xl space-y-4" @submit.prevent="submit">
    <div
      v-for="feature in features"
      :key="feature.id"
      class="flex items-start justify-between gap-4 rounded-lg border border-border bg-card p-4"
    >
      <div class="min-w-0 space-y-1">
        <p class="font-medium leading-none">{{ feature.label }}</p>
        <p class="text-sm text-muted-foreground">{{ feature.description }}</p>
      </div>
      <label class="flex shrink-0 cursor-pointer items-center gap-2 text-sm">
        <Checkbox v-model="form.features[feature.id]" />
        <span>{{ form.features[feature.id] ? '已启用' : '已关闭' }}</span>
      </label>
    </div>

    <p v-if="portalBothDisabled" class="text-sm text-destructive">
      论坛和商城不能同时关闭，否则用户登录后将无处可去。
    </p>

    <div class="flex flex-wrap items-center justify-end gap-3 pt-2 sm:justify-start">
      <Button type="submit" :disabled="form.processing || portalBothDisabled">保存开关</Button>
      <p v-if="form.recentlySuccessful" class="text-sm text-muted-foreground">已保存</p>
    </div>
  </form>
</template>
