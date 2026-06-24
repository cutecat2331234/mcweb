<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Textarea from '@/components/ui/Textarea.vue'

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
  <PageHeader :title="title" />
  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="name">{{ t('admin.common.name') }}</Label>
      <Input id="name" v-model="form.badge.name" required />
    </div>
    <div class="space-y-2">
      <Label for="slug">{{ t('admin.forms.tag.slug') }}</Label>
      <Input id="slug" v-model="form.badge.slug" required />
    </div>
    <div class="space-y-2">
      <Label for="icon">{{ t('admin.forms.badge.icon') }}</Label>
      <Input id="icon" v-model="form.badge.icon" />
    </div>
    <div class="space-y-2">
      <Label for="color">{{ t('admin.forms.badge.color') }}</Label>
      <Input id="color" v-model="form.badge.color" placeholder="#6366f1" />
    </div>
    <div class="space-y-2">
      <Label for="tier">{{ t('admin.forms.badge.tier') }}</Label>
      <Select id="tier" v-model="form.badge.tier" :options="tierOptions" block />
    </div>
    <div class="space-y-2">
      <Label for="grouping">{{ t('admin.forms.badge.grouping') }}</Label>
      <Input id="grouping" v-model="form.badge.grouping" :placeholder="t('admin.forms.badge.groupingPlaceholder')" />
    </div>
    <div class="space-y-2">
      <Label for="grant_rule">{{ t('admin.forms.badge.grantRule') }}</Label>
      <Select id="grant_rule" v-model="form.badge.grant_rule" :options="grantRuleOptions" block />
    </div>
    <div class="space-y-2">
      <Label for="grant_threshold">{{ t('admin.forms.badge.grantThreshold') }}</Label>
      <Input id="grant_threshold" v-model.number="form.badge.grant_threshold" type="number" min="0" />
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.common.description') }}</Label>
      <Textarea id="description" v-model="form.badge.description" rows="3" />
    </div>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline"><Link :href="backUrl">{{ t('admin.ui.back') }}</Link></Button>
    </div>
  </form>
</template>
