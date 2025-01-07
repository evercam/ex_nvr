<script lang="ts">
import {defineComponent} from 'vue'

const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

export default defineComponent({
  name: 'TimelineWrapper',
  props: {
    segments: Array,
  },
  data() {
    return {
      minDate: 0,
      endDate: Infinity,
      weekIndex: -1,
      totalWeeks: 0,
      ranges: [],
      eventGroups: {}
    }
  },
  mounted() {
    this.formatSegments()
  },
  watch: {
    segments: "formatSegments",
    weekIndex: "setEventGroups",
  },
  computed: {
    weekStart() {
      console.log(new Date(this.minDate + (604800000 * this.weekIndex)))
      return this.minDate + (604800000 * this.weekIndex)
    },
    weekEnd() {
      return this.minDate + (604800000 * (this.weekIndex + 1))
    }
  },
  methods: {
    setEventGroups() {      
      this.eventGroups = days.reduce((acc: any, day, index)=> {
        acc[day] = {
          label: day,
          color: "#eee",
          events: this.ranges.filter((range: any) => {
            return (new Date(range.startDate)).getDay() === index && 
              (this.weekStart <= range.startDate ||
              this.weekEnd >= range.endDate)
          }).map((range: any) => {
            return {
              ...range, 
              startDate: this.updateDatePreserveTime(new Date(this.weekStart), range.startDate),
              endDate: this.updateDatePreserveTime(new Date(this.weekStart), range.endDate),
            }
          })
        }
        return acc
      }, {})

      console.log(this.eventGroups)
    },
    formatSegments() {
      let maxDate = -Infinity 
      let minDate = Infinity

      const ranges = this.segments.reduce((acc, range) => {
        let startDate = (new Date(range.start_date)).getTime()
        let endDate = (new Date(range.end_date)).getTime()
        if (startDate > endDate) {
          const temp = startDate
          startDate = endDate
          endDate = temp
        }
        acc.push({
          startDate: startDate,
          endDate: endDate,
          color: "#5f6b43",
          text: "",
        })

        maxDate = Math.max(maxDate, endDate)
        minDate = Math.min(minDate, startDate)

        return acc
      }, [])

      this.minDate = this.getStartOfWeek(new Date(minDate))
      this.endDate = this.getEndOfWeek(new Date(maxDate)) 
      this.ranges = ranges

      this.totalWeeks = Math.round((this.endDate - this.minDate) / 604800000) // total milliseconds in a week

      if (this.weekIndex === -1) {
        this.weekIndex = this.totalWeeks - 1
      }

      return {ranges, maxDate: this.getEndOfWeek(new Date(maxDate)), minDate: this.getStartOfWeek(new Date(minDate))}
    },
    getStartOfWeek(date = new Date(), weekStart = 0) {
      const day = date.getDay()
      const diff = (day < weekStart ? 7 : 0) + day - weekStart
      const startOfWeek = new Date(date.getFullYear(), date.getMonth(), date.getDate() - diff);
      startOfWeek.setHours(0, 0, 0, 0)
      return startOfWeek.getTime()
    },
    getEndOfWeek(date = new Date(), weekStart = 0) {
      const startOfWeek = this.getStartOfWeek(date, weekStart)
      const endOfWeek = new Date(startOfWeek + 7 * 24 * 60 * 60 * 1000 - 1)
      return endOfWeek.getTime()
    },
    timestampToIsoString(timestamp: number) {
      console.log(this.formatDateToISO(new Date(timestamp)))
      return this.formatDateToISO(new Date(timestamp))
    },
    nextDay(timestamp: number) {
      return timestamp + 86400000 - 1
    },
    updateDatePreserveTime(sourceDate: Date, targetDate: Date): Date {
      const updatedDate = new Date(targetDate)
      updatedDate.setFullYear(sourceDate.getFullYear())
      updatedDate.setMonth(sourceDate.getMonth())
      updatedDate.setDate(sourceDate.getDate())
      return updatedDate;
    },
    formatDateToISO(date: Date): string {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      const seconds = String(date.getSeconds()).padStart(2, '0');

      return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}`;
    },
    formatToHHMM(date: Date): string {
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      return `${hours}:${minutes}`;
    },
    displayRange(range: any) {
      const start = new Date(range.startDate)
      const end = new Date(range.endDate)

      return `${this.formatToHHMM(start)} - ${this.formatToHHMM(end)}`
    }
  }
})
</script>

<template>
  <div v-if="weekIndex !== -1" class="timeline-container" style="width: 100%">
    <ETimeline
        :events-groups="eventGroups"
        :bar-height="35"
        :bar-y-padding="15"
        :only-hourly="true"
        :min-date="timestampToIsoString(weekStart)"
        :max-date="timestampToIsoString(nextDay(weekStart))"
        dark
    >
      <template #eventTooltip="{event, active}">
        <div 
          v-if="active" 
          class="e-timeline__event-tooltip e-border e-rounded e-px-2 -e-left-2/4 e-relative e-bg-gray-900 e-text-white e-border-gray-700"
        >
          {{ displayRange(event) }}
        </div>
      </template>

      <template #tooltip="{timestamp, hoveredGroupId, active}">
        <div 
          v-if="active" 
          class="e-timeline__tooltip e-border e-rounded e-px-2 -e-left-2/4 e-relative e-bg-gray-900 e-text-white e-border-gray-700"
        >
          hello {{ hoveredGroupId }}
        </div>
      </template>
    </ETimeline>
  </div>
</template>

<style scoped>
.timeline-container {
  clip-path: inset(-100px 0px 0px 0px);
}
</style>