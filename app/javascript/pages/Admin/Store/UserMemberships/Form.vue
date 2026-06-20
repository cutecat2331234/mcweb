<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  membership_types: Array<{ id: number; name: string }>
  submitUrl: string
  backUrl: string
}>()

const form = useForm({
  user_membership: {
    username: '',
    membership_type_id: props.membership_types[0]?.id ?? null,
    grant_game_permissions: true,
  },
})

const typeOptions = props.membership_types.map((type) => ({
  value: String(type.id),
  label: type.name,
}))

function submit() {
  form.post(props.submitUrl)
}
</script>

<template>
  <PageHeader :title="title" />

  <form class="max-w-lg space-y-4" @submit.prevent="submit">
    <div class="space-y-2">
      <Label for="username">{{ t('admin.forms.userMembership.username') }}</Label>
      <Input id="username" v-model="form.user_membership.username" required />
    </div>
    <div class="space-y-2">
      <Label for="membership_type_id">{{ t('admin.forms.userMembership.type') }}</Label>
      <Select
        id="membership_type_id"
        :model-value="form.user_membership.membership_type_id == null ? '' : String(form.user_membership.membership_type_id)"
        :options="typeOptions"
        block
        @update:model-value="(v) => form.user_membership.membership_type_id = v ? Number(v) : null"
      />
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.user_membership.grant_game_permissions" />
      {{ t('admin.forms.userMembership.grantGamePermissions') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.forms.userMembership.grant') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
