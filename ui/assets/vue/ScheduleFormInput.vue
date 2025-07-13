<template>
  <div>
    <div class="flex gap-4 mt-1">
      <label class="block font-medium text-black dark:text-white mt-1">Schedule</label>
      <label class="inline-flex items-center">
        <!-- @input.stop @change.stop used to stop triggering phx-change event of the form -->
        <input
          type="radio"
          value="default"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
          v-model="schedule_mode"
          @input.stop 
          @change.stop
        />
        <span class="ml-2 text-black dark:text-white">Default</span>
      </label>

      <label class="inline-flex items-center" phx-ignore>
        <input
          type="radio"
          value="custom"
          class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
          v-model="schedule_mode"
          @input.stop
          @change.stop
        />
        <span class="ml-2 text-black dark:text-white">Custom</span>
      </label>
    </div>

    <div v-if="!default_schedule" class="-ml-4">
      <Schedule :schedule=form_field.value @change="handle_schedule_change" />
      <input type="hidden" :id=form_field.id :name=form_field.name :value=form_field_value />
    </div>
  </div>
</template>

<script lang="ts">
import type {PropType} from "vue"
import { defineComponent } from 'vue';
import Schedule from './Schedule.vue'

type FormField = {
  id: string;
  name: string;
  value: Record<string, string[]> | undefined;
}

export default defineComponent({
  props: {
    form_field: {
      type: Object as PropType<FormField>,
      required: true,
    },
  },
  components: {
    Schedule
  },
  computed: {
    form_field_value() {
      return this.form_field.value && JSON.stringify(this.form_field.value);
    },
    default_schedule() {
      return this.schedule_mode == 'default';
    }
  },
  watch: {
    schedule_mode(newValue) {
      if (newValue === 'default') {
        this.form_field.value = undefined;
      }
    }
  },
  data() {
    return {
      schedule_mode: this.form_field.value ? 'custom' : 'default',
    }
  },
  methods: {
    handle_schedule_change(schedule : Record<string, string[]>) {
      this.form_field.value = schedule;
    }
  }
});
</script>