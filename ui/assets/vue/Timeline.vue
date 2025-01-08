<script>
import {defineComponent} from 'vue'

const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

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
      eventGroups: {},
      loading: false,
      barColor: "#4dc007"
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
      return this.minDate + (604800000 * this.weekIndex)
    },
    weekEnd() {
      return this.minDate + (604800000 * (this.weekIndex + 1))
    }
  },
  methods: {
    setEventGroups() {      
      this.eventGroups = days.reduce((acc, day, index)=> {
        acc[day] = {
          label: day,
          color: "#eee",
          events: this.ranges.filter((range) => {
            return (new Date(range.startDate)).getDay() === index && this.rangeIncluded(range)
          }).map((range) => {
            return {
              ...range, 
              startDate: this.updateDatePreserveTime(new Date(this.weekStart), range.startDate),
              endDate: this.updateDatePreserveTime(new Date(this.weekStart), range.endDate),
            }
          })
        }
        return acc
      }, {})
    },
    rangeIncluded(range) {
      return (this.weekStart <= range.startDate && range.startDate <= this.weekEnd) || (this.weekStart <= range.endDate && range.endDate <= this.weekEnd)
    },
    formatSegments() {
      let maxDate = -Infinity 
      let minDate = Infinity

      this.ranges = this.segments?.reduce((acc, range) => {
        let startDate = new Date(range.start_date)
        let endDate = new Date(range.end_date)

        maxDate = Math.max(maxDate, endDate.getTime())
        minDate = Math.min(minDate, startDate.getTime())

        if (startDate.getTime() > endDate.getTime()) {
          const temp = startDate
          startDate = endDate
          endDate = temp
        }
        if (startDate.toDateString() === endDate.toDateString()) {
          acc.push({
            startDate: startDate.getTime(),
            endDate: endDate.getTime(),
            color: this.barColor,
            text: "",
          })
        } else {
          while (startDate.toDateString() !== endDate.toDateString()) {
            const endOfDay = new Date(startDate)
            endOfDay.setHours(23, 59, 59, 999)

            acc.push({
              startDate: startDate.getTime(),
              endDate: endOfDay.getTime(),
              color: this.barColor,
              text: "",
            })

            startDate = new Date(endOfDay);
            startDate.setDate(startDate.getDate() + 1);
            startDate.setHours(0, 0, 0, 0);
          }

          acc.push({
            startDate: startDate.getTime(),
            endDate: endDate.getTime(),
            color: this.barColor,
            text: "",
          })
        }

        return acc
      }, [])

      this.minDate = this.getStartOfWeek(new Date(minDate))
      this.endDate = this.getEndOfWeek(new Date(maxDate)) 

      this.totalWeeks = Math.round((this.endDate - this.minDate) / 604800000) // total milliseconds in a week

      if (this.weekIndex === -1) {
        this.weekIndex = this.totalWeeks - 1
      }
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
    timestampToIsoString(timestamp, onlyDate = false) {
      if (onlyDate) {
        return this.formatToDate(new Date(timestamp))
      } else {
        return this.formatDateToISO(new Date(timestamp))
      }
    },
    nextDay(timestamp) {
      return timestamp + 86400000 - 1
    },
    updateDatePreserveTime(sourceDate, targetDate) {
      const updatedDate = new Date(targetDate)
      updatedDate.setFullYear(sourceDate.getFullYear())
      updatedDate.setMonth(sourceDate.getMonth())
      updatedDate.setDate(sourceDate.getDate())
      return updatedDate;
    },
    formatToDate(date) {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');

      return `${year}-${month}-${day}`;
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
    formatToHHMM(date) {
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      return `${hours}:${minutes}`;
    },
    displayRange(range) {
      const start = new Date(range.startDate)
      const end = new Date(range.endDate)

      return `${this.formatToHHMM(start)} - ${this.formatToHHMM(end)}`
    },
    incrementIndex(increment) {
      if (this.weekIndex + increment < 0 || this.weekIndex + increment >= this.totalWeeks) {
        return
      }
      this.loading = true

      this.weekIndex += increment
      setTimeout(() => this.loading = false, 50)
    }
  }
})
</script>

<template>
  <div v-if="weekIndex !== -1" class="timeline-container" style="width: 100%">
    <ERow align="center">
      <EActionButton
        tooltip-text="Previous"
        tooltip-position="bottom"
        icon="fas fa-angle-left"
        :dark="true"
        icon-size="Base"
        @click.stop="incrementIndex(-1)"
      />
      <div class="mx-2 e-text-white"> 
        {{ weekIndex + 1 }} / {{ totalWeeks }} 
        <span class="e-text-xs">
          (
            {{ timestampToIsoString(weekStart, true) }} - {{ timestampToIsoString(weekEnd, true) }}
          )
        </span>
      </div>
      <EActionButton
        tooltip-text="Next"
        tooltip-position="bottom"
        icon="fas fa-angle-right"
        :dark="true"
        icon-size="Base"
        @click.stop="incrementIndex(1)"
      />
    </ERow>
    <ETimeline
      v-if="!loading"
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

      <template #tooltip>
        <div></div>
      </template>
    </ETimeline>
  </div>
</template>

<style scoped>
</style>