<script setup lang="ts">
import { useForm, Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

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
  <a-page-header
    :title="t('admin.forum.points.settingsTitle')"
    :subtitle="t('admin.forum.points.settingsSubtitle')"
    :show-back="false"
    class="mb-4 !px-0"
  >
    <template #extra>
      <Link :href="back_url" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">
        {{ t('admin.forum.points.backToLog') }}
      </Link>
    </template>
  </a-page-header>

  <a-card class="max-w-xl" :bordered="true">
    <form class="grid gap-5" @submit.prevent="submit">
      <label v-for="item in settings" :key="item.key" class="admin-forum-field">
        <span>{{ item.label }}</span>
        <a-input-number
          :model-value="form.settings[item.key] === '' ? undefined : Number(form.settings[item.key])"
          :min="0"
          class="w-full sm:w-48"
          @update:model-value="(value: number | undefined) => { form.settings[item.key] = value == null ? '' : String(value) }"
        />
        <small v-if="item.hint">{{ item.hint }}</small>
      </label>

      <a-space>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('admin.common.saveSettings') }}
        </a-button>
        <a-tag v-if="form.recentlySuccessful" color="green">{{ t('admin.common.saved') }}</a-tag>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field {
  display: grid;
  gap: 6px;
  color: var(--color-text-2);
  font-size: 14px;
}

.admin-forum-field small {
  color: var(--color-text-3);
}
</style>
