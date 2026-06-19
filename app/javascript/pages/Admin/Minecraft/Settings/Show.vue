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
  }
  updateUrl: string
}>()

const { t } = useI18n()

const form = useForm({
  link_command: props.settings.link_command,
  skin_mode: props.settings.skin_mode,
  bridges_enabled: props.settings.bridges_enabled,
  bridge_placeholders: props.settings.bridge_placeholders,
  profile_sections: props.settings.profile_sections,
})

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
      <Button type="submit" :disabled="form.processing">{{ t('common.save') }}</Button>
    </form>
  </div>
</template>
