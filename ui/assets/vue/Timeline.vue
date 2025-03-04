<script>
import {defineComponent} from 'vue'

export default defineComponent({
  name: 'Timeline',
  props: {
    segments: Array,
    timezone: {
      type: String,
      default: "",
    }
  },
  data() {
    return {
      startDate: "",
      endDate: "",
      minDate: "2023",
      maxDate: "2025",
      focusedInterval: {},
      eventGroups: {Runs: {}},
      barColor: "#4dc007"
    }
  },
  mounted() {
    this.setEventGroups()
  },
  watch: {
    segments: "setEventGroups",
  },
  methods: {
    setEventGroups() {  
      this.eventGroups.Runs = {
        label: "Runs",
        color: "#eee",
        events: this.formatSegments()
      }
    },
    formatSegments() {
      let maxDate = 0 
      let minDate = Infinity

      const formatedRanges = this.segments?.reduce((acc, range) => {
        let startDate = new Date(range.start_date)
        let endDate = new Date(range.end_date)

        if (startDate.getTime() > endDate.getTime()) {
          const temp = startDate
          startDate = endDate
          endDate = temp
        }

        maxDate = Math.max(maxDate, endDate.getTime())
        minDate = Math.min(minDate, startDate.getTime())

        acc.push({
          startDate: startDate.getTime(),
          endDate: endDate.getTime(),
          color: this.barColor,
          text: "",
        })

        return acc
      }, [])

      if (!this.startDate) {
        this.minDate = this.formatDateToISO(this.addYear(new Date(minDate), -1))
        this.maxDate = this.formatDateToISO(this.addYear(new Date(maxDate), 2))
      }

      return formatedRanges
    },
    formatDateToISO(date, spacing = "T") {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      const seconds = String(date.getSeconds()).padStart(2, '0');

      return `${year}-${month}-${day}${spacing}${hours}:${minutes}:${seconds}`;
    },
    addYear(initialDate, years) {
      const date = new Date(initialDate)
      date.setFullYear(date.getFullYear() + years)

      return date
    },
  },
})
</script>

<template>
  <div v-if="eventGroups.Runs?.events" class="mt-3" style="width: 100%">
    <ETimeline
      ref="timeline"
      :events-groups="eventGroups"
      :bar-height="35"
      :bar-y-padding="15"
      :show-labels="false"
      :min-date="minDate"
      :max-date="maxDate"
      :timezone="timezone"
      @event-clicked="$emit('run-clicked', $event)"
      dark
    >
      <template #tooltip="{timestamp, active}">
        <div v-if="active" class="e-border e-rounded e-px-2 -e-left-2/4 e-relative e-bg-gray-900 e-text-white e-border-gray-700 e-p-3">
          {{ formatDateToISO(new Date(timestamp), " ") }}
        </div>
      </template>

      <template #eventTooltip="{ active, timestamp}">
        <div v-if="active" class="e-border e-rounded e-px-2 -e-left-2/4 e-relative e-bg-gray-900 e-text-white e-border-gray-700 e-p-3">
          {{ formatDateToISO(new Date(timestamp), " ") }}
        </div>
      </template>
    </ETimeline>
  </div>
</template>