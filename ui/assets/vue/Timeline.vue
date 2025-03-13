<script>
import {defineComponent} from 'vue'
import * as moment from 'moment-timezone'

export default defineComponent({
  name: 'Timeline',
  props: {
    segments: Array,
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
        let startDate = moment.utc(range.start_date)
        let endDate = moment.utc(range.end_date)

        if (startDate.isAfter(endDate)) {
          const temp = startDate
          startDate = endDate
          endDate = temp
        }

        maxDate = Math.max(maxDate, endDate.unix())
        minDate = Math.min(minDate, startDate.unix())

        acc.push({
          startDate: startDate.toISOString(),
          endDate: endDate.toISOString(),
          color: this.barColor,
          text: "",
        })

        return acc
      }, [])

      if (!this.startDate) {
        this.minDate = moment.unix(minDate).subtract(1, "years").format("YYYY-MM-DD[T]HH:mm:ss")
        this.maxDate = moment.unix(maxDate).add(1, "years").format("YYYY-MM-DD[T]HH:mm:ss")
      }

      return formatedRanges
    },
    formatDateToISO(date) {
      return moment.utc(date).format("YYYY-MM-DD HH:mm:ss")
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
      @event-clicked="$emit('run-clicked', $event)"
      dark
    >
      <template #tooltip="{timestamp, active}">
        <div v-if="active" class="e-border e-rounded e-px-2 -e-left-2/4 e-relative e-bg-gray-900 e-text-white e-border-gray-700 e-p-3">
          {{ formatDateToISO(timestamp) }}
        </div>
      </template>

      <template #eventTooltip="{ active, timestamp}">
        <div v-if="active" class="e-border e-rounded e-px-2 -e-left-2/4 e-relative e-bg-gray-900 e-text-white e-border-gray-700 e-p-3">
          {{ formatDateToISO(timestamp) }}
        </div>
      </template>
    </ETimeline>
  </div>
</template>