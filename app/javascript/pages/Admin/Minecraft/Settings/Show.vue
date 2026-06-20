<script setup lang="ts">
import { useForm } from '@inertiajs/vue3'
import { useI18n } from 'vue-i18n'
import AdminLayout from '@/layouts/AdminLayout.vue'
import Button from '@/components/ui/Button.vue'
import Input from '@/components/ui/Input.vue'
import Label from '@/components/ui/Label.vue'
import Select from '@/components/ui/Select.vue'

defineOptions({ layout: AdminLayout })

const props = defineProps<{
  settings: {
    link_command: string
    skin_mode: string
    bridges_enabled: string
    bridge_placeholders: string
    profile_sections: string
    graceful_stop_enabled: string
    graceful_stop_countdown: string
    graceful_stop_message: string
    graceful_stop_commands: string
    exec_command_allowed_prefixes: string
    pause_fulfill_during_maintenance: string
    backup_enabled: string
    backup_schedule: string
  }
  updateUrl: string
}>()

const { t } = useI18n()

const form = useForm({ ...props.settings })

function submit() {
  form.patch(props.updateUrl)
}
</script>

<template>
  <div class="max-w-2xl space-y-6">
    <h1 class="text-2xl font-semibold">{{ t('adminMinecraft.title') }}</h1>
    <form class="space-y-4" @submit.prevent="submit">
      <div>
        <Label for="link_command">{{ t('adminMinecraft.linkCommand') }}</Label>
        <Input id="link_command" v-model="form.link_command" />
      </div>
      <div>
        <Label for="skin_mode">{{ t('adminMinecraft.skinMode') }}</Label>
        <Select
          id="skin_mode"
          v-model="form.skin_mode"
          :options="[
            { value: '2d', label: t('adminMinecraft.skin2d') },
            { value: '3d', label: t('adminMinecraft.skin3d') },
            { value: 'both', label: t('adminMinecraft.skinBoth') },
          ]"
        />
      </div>
      <div>
        <Label for="bridges_enabled">{{ t('adminMinecraft.bridgesEnabled') }}</Label>
        <Input id="bridges_enabled" v-model="form.bridges_enabled" />
      </div>
      <div>
        <Label for="bridge_placeholders">{{ t('adminMinecraft.bridgePlaceholders') }}</Label>
        <Input id="bridge_placeholders" v-model="form.bridge_placeholders" placeholder="%player_level%,%vault_eco_balance%" />
      </div>
      <div>
        <Label for="profile_sections">{{ t('adminMinecraft.profileSections') }}</Label>
        <Input id="profile_sections" v-model="form.profile_sections" />
      </div>

      <h2 class="pt-4 text-lg font-semibold">{{ t('adminMinecraft.gracefulStopSection') }}</h2>
      <div>
        <Label for="graceful_stop_enabled">{{ t('adminMinecraft.gracefulStopEnabled') }}</Label>
        <Select
          id="graceful_stop_enabled"
          v-model="form.graceful_stop_enabled"
          :options="[
            { value: 'true', label: t('adminMinecraft.yes') },
            { value: 'false', label: t('adminMinecraft.no') },
          ]"
        />
      </div>
      <div>
        <Label for="graceful_stop_countdown">{{ t('adminMinecraft.gracefulStopCountdown') }}</Label>
        <Input id="graceful_stop_countdown" v-model="form.graceful_stop_countdown" type="number" min="0" />
      </div>
      <div>
        <Label for="graceful_stop_message">{{ t('adminMinecraft.gracefulStopMessage') }}</Label>
        <Input id="graceful_stop_message" v-model="form.graceful_stop_message" />
      </div>
      <div>
        <Label for="graceful_stop_commands">{{ t('adminMinecraft.gracefulStopCommands') }}</Label>
        <Input id="graceful_stop_commands" v-model="form.graceful_stop_commands" placeholder="save-all,stop" />
      </div>

      <h2 class="pt-4 text-lg font-semibold">{{ t('adminMinecraft.nodeOpsSection') }}</h2>
      <div>
        <Label for="exec_command_allowed_prefixes">{{ t('adminMinecraft.execAllowedPrefixes') }}</Label>
        <Input id="exec_command_allowed_prefixes" v-model="form.exec_command_allowed_prefixes" placeholder="ls,tail,systemctl" />
      </div>
      <div>
        <Label for="pause_fulfill_during_maintenance">{{ t('adminMinecraft.pauseFulfillMaintenance') }}</Label>
        <Select
          id="pause_fulfill_during_maintenance"
          v-model="form.pause_fulfill_during_maintenance"
          :options="[
            { value: 'true', label: t('adminMinecraft.yes') },
            { value: 'false', label: t('adminMinecraft.no') },
          ]"
        />
      </div>
      <div>
        <Label for="backup_enabled">{{ t('adminMinecraft.backupEnabled') }}</Label>
        <Select
          id="backup_enabled"
          v-model="form.backup_enabled"
          :options="[
            { value: 'true', label: t('adminMinecraft.yes') },
            { value: 'false', label: t('adminMinecraft.no') },
          ]"
        />
      </div>
      <div>
        <Label for="backup_schedule">{{ t('adminMinecraft.backupSchedule') }}</Label>
        <Input id="backup_schedule" v-model="form.backup_schedule" placeholder="0 3 * * *" />
      </div>

      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
    </form>
  </div>
</template>
