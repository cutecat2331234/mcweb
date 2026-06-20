<script setup lang="ts">
import { Link, useForm } from '@inertiajs/vue3'
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import PageHeader from '@/components/portal/PageHeader.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Textarea from '@/components/ui/Textarea.vue'
import Select from '@/components/ui/Select.vue'
import Checkbox from '@/components/ui/Checkbox.vue'

defineOptions({ layout: AdminLayout })

const { t } = useI18n()

const props = defineProps<{
  title: string
  membership_type: {
    id?: number
    slug: string
    name: string
    description: string
    color: string
    icon: string
    duration_mode: string
    duration_days: number
    luckperms_group: string
    game_permission_enabled: boolean
    game_permission_mode: string
    grant_commands: string
    revoke_commands: string
    display_priority: number
    active: boolean
  }
  submitUrl: string
  method: 'post' | 'patch'
  backUrl: string
}>()

const form = useForm({ membership_type: { ...props.membership_type } })

const durationModeOptions = computed(() => [
  { value: 'fixed_days', label: t('admin.forms.membershipType.durationFixed') },
  { value: 'permanent', label: t('admin.forms.membershipType.durationPermanent') },
])

const gamePermissionModeOptions = computed(() => [
  { value: 'website_managed', label: t('admin.forms.membershipType.gameModeWebsite') },
  { value: 'lp_timed', label: t('admin.forms.membershipType.gameModeLpTimed') },
])

function fillDefaultGrant() {
  const group = form.membership_type.luckperms_group || form.membership_type.slug || 'vip'
  if (form.membership_type.game_permission_mode === 'lp_timed') {
    form.membership_type.grant_commands = JSON.stringify([`lp user {player} parent addtemp ${group} {duration}`], null, 2)
  } else {
    form.membership_type.grant_commands = JSON.stringify([`lp user {player} parent add ${group}`], null, 2)
  }
}

function fillDefaultRevoke() {
  const group = form.membership_type.luckperms_group || form.membership_type.slug || 'vip'
  form.membership_type.revoke_commands = JSON.stringify([`lp user {player} parent remove ${group}`], null, 2)
}

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
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="name">{{ t('admin.common.name') }}</Label>
        <Input id="name" v-model="form.membership_type.name" required />
      </div>
      <div class="space-y-2">
        <Label for="slug">{{ t('admin.common.slugFull') }}</Label>
        <Input id="slug" v-model="form.membership_type.slug" required />
      </div>
    </div>
    <div class="space-y-2">
      <Label for="description">{{ t('admin.common.description') }}</Label>
      <Textarea id="description" v-model="form.membership_type.description" rows="2" />
    </div>
    <div class="grid grid-cols-3 gap-4">
      <div class="space-y-2">
        <Label for="color">{{ t('admin.forms.membershipType.color') }}</Label>
        <Input id="color" v-model="form.membership_type.color" type="color" />
      </div>
      <div class="space-y-2">
        <Label for="icon">{{ t('admin.forms.membershipType.icon') }}</Label>
        <Input id="icon" v-model="form.membership_type.icon" maxlength="8" :placeholder="t('admin.forms.membershipType.icon')" />
      </div>
      <div class="space-y-2">
        <Label for="display_priority">{{ t('admin.forms.membershipType.displayPriority') }}</Label>
        <Input id="display_priority" v-model.number="form.membership_type.display_priority" type="number" />
      </div>
    </div>
    <div class="grid grid-cols-2 gap-4">
      <div class="space-y-2">
        <Label for="duration_mode">{{ t('admin.forms.membershipType.durationMode') }}</Label>
        <Select id="duration_mode" v-model="form.membership_type.duration_mode" :options="durationModeOptions" block />
      </div>
      <div v-if="form.membership_type.duration_mode === 'fixed_days'" class="space-y-2">
        <Label for="duration_days">{{ t('admin.forms.membershipType.durationDays') }}</Label>
        <Input id="duration_days" v-model.number="form.membership_type.duration_days" type="number" min="1" />
      </div>
    </div>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.membership_type.game_permission_enabled" />
      {{ t('admin.forms.membershipType.gamePermissionEnabled') }}
    </label>
    <template v-if="form.membership_type.game_permission_enabled">
      <div class="space-y-2">
        <Label for="game_permission_mode">{{ t('admin.forms.membershipType.gamePermissionMode') }}</Label>
        <Select id="game_permission_mode" v-model="form.membership_type.game_permission_mode" :options="gamePermissionModeOptions" block />
      </div>
      <div class="space-y-2">
        <Label for="luckperms_group">{{ t('admin.forms.membershipType.luckpermsGroup') }}</Label>
        <Input id="luckperms_group" v-model="form.membership_type.luckperms_group" />
      </div>
      <div class="space-y-2">
        <div class="flex items-center justify-between">
          <Label for="grant_commands">{{ t('admin.forms.membershipType.grantCommands') }}</Label>
          <Button type="button" variant="outline" size="sm" @click="fillDefaultGrant">{{ t('admin.forms.membershipType.fillDefault') }}</Button>
        </div>
        <Textarea id="grant_commands" v-model="form.membership_type.grant_commands" rows="4" class="font-mono text-xs" />
        <p class="text-xs text-muted-foreground">{{ t('admin.forms.membershipType.commandsHint') }}</p>
      </div>
      <div class="space-y-2">
        <div class="flex items-center justify-between">
          <Label for="revoke_commands">{{ t('admin.forms.membershipType.revokeCommands') }}</Label>
          <Button type="button" variant="outline" size="sm" @click="fillDefaultRevoke">{{ t('admin.forms.membershipType.fillDefault') }}</Button>
        </div>
        <Textarea id="revoke_commands" v-model="form.membership_type.revoke_commands" rows="3" class="font-mono text-xs" />
        <p class="text-xs text-muted-foreground">{{ t('admin.forms.membershipType.commandsHint') }}</p>
      </div>
    </template>
    <label class="flex items-center gap-2 text-sm">
      <Checkbox v-model="form.membership_type.active" />
      {{ t('admin.common.enable') }}
    </label>
    <div class="flex gap-2">
      <Button type="submit" :disabled="form.processing">{{ t('admin.ui.save') }}</Button>
      <Button as-child variant="outline">
        <Link :href="backUrl">{{ t('admin.ui.cancel') }}</Link>
      </Button>
    </div>
  </form>
</template>
