<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  badge: {
    id?: number
    name: string
    slug: string
    description: string
    icon: string
    color: string
    grant_rule: string
    grant_threshold: number
    tier: string
    grouping: string
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ badge: { ...props.badge } })

const tierOptions = computed(() => [
  { value: 'bronze', label: t('admin.forms.badge.tierBronze') },
  { value: 'silver', label: t('admin.forms.badge.tierSilver') },
  { value: 'gold', label: t('admin.forms.badge.tierGold') },
])

const grantRuleOptions = computed(() => [
  { value: 'manual', label: t('admin.forms.badge.ruleManual') },
  { value: 'first_topic', label: t('admin.forms.badge.ruleFirstTopic') },
  { value: 'posts_count', label: t('admin.forms.badge.rulePostsCount') },
  { value: 'likes_received', label: t('admin.forms.badge.ruleLikesReceived') },
  { value: 'first_purchase', label: t('admin.forms.badge.ruleFirstPurchase') },
  { value: 'trust_level', label: t('admin.forms.badge.ruleTrustLevel') },
  { value: 'member_days', label: t('admin.forms.badge.ruleMemberDays') },
  { value: 'solutions', label: t('admin.forms.badge.ruleSolutions') },
  { value: 'topics_count', label: t('admin.forms.badge.ruleTopicsCount') },
  { value: 'reactions_given', label: t('admin.forms.badge.ruleReactionsGiven') },
  { value: 'first_reply', label: t('admin.forms.badge.ruleFirstReply') },
])

function submit() {
  if (props.method === 'patch') form.patch(props.submitUrl)
  else form.post(props.submitUrl)
}
</script>

<template>
  <a-page-header :title="title" :show-back="false" class="mb-4 !px-0" />
  <a-card class="max-w-3xl" :bordered="true">
    <form class="grid gap-4" @submit.prevent="submit">
      <a-row :gutter="[16, 0]">
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.common.name') }}</span>
            <a-input v-model="form.badge.name" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.tag.slug') }}</span>
            <a-input v-model="form.badge.slug" :input-attrs="{ required: true }" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.badge.icon') }}</span>
            <a-input v-model="form.badge.icon" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.badge.color') }}</span>
            <a-input v-model="form.badge.color" placeholder="#6366f1" allow-clear />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.badge.tier') }}</span>
            <a-select v-model="form.badge.tier" :options="tierOptions" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.badge.grouping') }}</span>
            <a-input
              v-model="form.badge.grouping"
              :placeholder="t('admin.forms.badge.groupingPlaceholder')"
              allow-clear
            />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.badge.grantRule') }}</span>
            <a-select v-model="form.badge.grant_rule" :options="grantRuleOptions" />
          </label>
        </a-col>
        <a-col :xs="24" :sm="12">
          <label class="admin-forum-field">
            <span>{{ t('admin.forms.badge.grantThreshold') }}</span>
            <a-input-number v-model="form.badge.grant_threshold" :min="0" class="w-full" />
          </label>
        </a-col>
      </a-row>
      <label class="admin-forum-field">
        <span>{{ t('admin.common.description') }}</span>
        <a-textarea v-model="form.badge.description" :auto-size="{ minRows: 3, maxRows: 7 }" />
      </label>
      <a-space wrap>
        <a-button html-type="submit" type="primary" :loading="form.processing">{{ t('admin.ui.save') }}</a-button>
        <Link :href="backUrl" class="arco-btn arco-btn-outline arco-btn-size-medium no-underline">{{ t('admin.ui.back') }}</Link>
      </a-space>
    </form>
  </a-card>
</template>

<style scoped>
.admin-forum-field { display: grid; gap: 6px; color: var(--color-text-2); font-size: 14px; }
</style>
