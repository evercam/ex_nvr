<script>
import {defineComponent} from 'vue'

export default defineComponent({
  name: 'Timeline',
  props: {
    segments: Array,
  },
  data() {
    return {
      minDate: "",
      endDate: "",
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

      this.minDate = this.formatDateToISO(this.addDay(new Date(minDate), 7))
      this.endDate = this.formatDateToISO(this.addDay(new Date(maxDate), -7))

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
    addDay(date, days) {
      date.setDate(date.getDate() + 1)

      return date
    }
  },
})
</script>

<template>
  <div v-if="eventGroups" class="timeline-container" style="width: 100%">
    <ETimeline
      :events-groups="eventGroups"
      :bar-height="35"
      :bar-y-padding="15"
      :min-date="minDate"
      :max-date="endDate"
      dark
    />
  </div>
</template>

<style scoped>
</style>