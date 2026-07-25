<script setup lang="ts">
import { useForm, Link } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  save_url: string
  back_url: string
}>()

const form = useForm<{ username: string; amount: number | string; note: string }>({
  username: '',
  amount: '',
  note: '',
})

function submit() {
  form.post(props.save_url, { preserveScroll: true })
}
</script>

<template>
  <a-page-header
    :title="t('admin.forum.points.adjustTitle')"
    :subtitle="t('admin.forum.points.adjustSubtitle')"
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
    <form class="grid gap-4" @submit.prevent="submit">
      <label class="admin-forum-field">
        <span>{{ t('admin.forum.points.fieldUser') }}</span>
        <a-input v-model="form.username" :placeholder="t('admin.forum.points.fieldUserHint')" allow-clear />
        <small v-if="form.errors.username" class="text-[rgb(var(--danger-6))]">
          {{ form.errors.username }}
        </small>
      </label>

      <label class="admin-forum-field">
        <span>{{ t('admin.forum.points.fieldAmount') }}</span>
        <a-input-number
          :model-value="form.amount === '' ? undefined : Number(form.amount)"
          :placeholder="t('admin.forum.points.fieldAmountHint')"
          class="w-full sm:w-48"
          @update:model-value="(value: number | undefined) => { form.amount = value ?? '' }"
        />
        <small>{{ t('admin.forum.points.fieldAmountNote') }}</small>
      </label>

      <label class="admin-forum-field">
        <span>{{ t('admin.forum.points.fieldNote') }}</span>
        <a-input v-model="form.note" :placeholder="t('admin.forum.points.fieldNoteHint')" allow-clear />
      </label>

      <div>
        <a-button html-type="submit" type="primary" :loading="form.processing">
          {{ t('admin.forum.points.applyAdjustment') }}
        </a-button>
      </div>
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
