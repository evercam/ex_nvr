<script>
import {defineComponent} from 'vue'

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

      this.startDate = this.formatDateToISO(new Date(minDate))
      this.endDate = this.formatDateToISO(new Date(maxDate))
      this.minDate = this.formatDateToISO(this.addYear(new Date(minDate), -2))
      this.maxDate = this.formatDateToISO(this.addYear(new Date(maxDate), 2))

      return formatedRanges
    },
    formatDateToISO(date) {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      const seconds = String(date.getSeconds()).padStart(2, '0');

      return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}`;
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
  <div v-if="eventGroups" class="timeline-container" style="width: 100%">
    <ETimeline
      :events-groups="eventGroups"
      :bar-height="35"
      :bar-y-padding="15"
      :start-date="startDate"
      :end-date="endDate"
      :min-date="minDate"
      :max-date="maxDate"
      @event-clicked="$emit('run-clicked', $event)"
      dark
    />
  </div>
</template>

<style scoped>
</style>