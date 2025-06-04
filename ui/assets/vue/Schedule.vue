<template>
  <div ref="mainContainer" class="schedule text-white p-4 relative">
    <!-- Table -->
    <table
      ref="table"
      v-resize-observer="onResize"
      class="table-fixed w-full border-separate border-spacing-0 relative"
    >
      <thead>
        <tr class="h-8">
          <th class="w-16"></th>
          <th
            v-for="hour in 24"
            :key="hour"
            class="hour-label p-1 text-center h-8"
          >
            {{ formatHour(hour) }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(d, dayIndex) in sortedDays" :key="d.day" class="h-8">
          <th class="p-1 text-center h-8" scope="row">
            {{ formatDay(d.day) }}
          </th>

          <td
            v-for="hour in 24"
            :key="hour"
            class="segment-cell border-b border-white dark:border-gray-700 h-8"
            :class="{
              'border-l': hour === 1,
              'border-r': hour === 24,
              'border-t': dayIndex === 0,
              'rounded-tl-lg': dayIndex === 0 && hour === 1,
              'rounded-tr-lg': dayIndex === 0 && hour === 24,
              'rounded-bl-lg': dayIndex === sortedDays.length - 1 && hour === 1,
              'rounded-br-lg':
                dayIndex === sortedDays.length - 1 && hour === 24,
            }"
          ></td>
        </tr>
      </tbody>
    </table>

    <!-- Interactive overlay -->
    <div
      v-if="segmentsContainerRect"
      ref="overlay"
      class="absolute inset-0 cursor-crosshair"
      :style="segmentsContainerStyles"
      @mousedown="onBackgroundMouseDown"
    >
      <template v-for="(dayObj, dayIndex) in sortedDays" :key="dayObj.day">
        <div
          v-for="(segment, segmentIndex) in dayObj.segments"
          :key="segment.startTime + '-' + segment.endTime"
          :style="
            calculateBarStyle(dayIndex, segment.startTime, segment.endTime)
          "
          class="segment rounded absolute bg-blue-500/80"
          @mousedown.stop="onSegmentMouseDown($event, dayIndex, segmentIndex)"
          @mousemove="onSegmentMouseMove"
          @mouseleave="onSegmentMouseLeave"
        >
          <button
            class="delete-btn absolute top-0 right-0 m-1 text-xs bg-red-600 rounded text-white p-1 opacity-0 hover:opacity-100 transition-opacity"
            @click.stop="deleteSegment(dayIndex, segmentIndex)"
          >
            ✕
          </button>

          <div
            class="flex justify-center items-center text-xs text-white w-full h-full select-none"
          >
            {{ segment.startTime }} - {{ segment.endTime }}
          </div>
        </div>
      </template>
      <div
        v-if="creating"
        :style="
          calculateMultiDayStyle(
            creating.startDayIndex,
            creating.currentDayIndex,
            creating.startFrac,
            creating.currentFrac
          )
        "
        class="segment rounded absolute bg-blue-300/50 border border-blue-400 flex justify-center items-center text-xs text-white"
      >
        {{
          padTime(
            roundToFive(Math.min(creating.startFrac, creating.currentFrac))
          )
        }}
        &nbsp;-&nbsp;
        {{
          padTime(
            roundToFive(Math.max(creating.startFrac, creating.currentFrac))
          )
        }}
      </div>
    </div>
  </div>
</template>

<script lang="ts">
import { defineComponent } from "vue"
import type { PropType } from "vue"
import { ResizeObserverDirective } from "@evercam/ui"

type DayCode = 0 | 1 | 2 | 3 | 4 | 5 | 6

type ScheduleSegment = {
  startTime: string
  endTime: string
}

type DaySchedule = {
  day: DayCode
  segments: ScheduleSegment[]
}

export default defineComponent({
  name: "Schedule",
  directives: {
    ResizeObserver: ResizeObserverDirective,
  },
  props: {
    days: {
      type: Array as PropType<DaySchedule[]>,
      required: true
    },
  },
  data() {
    return {
      headerHeightPx: 48,
      rowHeightPx: 32,
      segmentsContainerRect: null as {
        top: number
        left: number
        width: number
        height: number
      } | null,

      editing: null as {
        dayIndex: number
        segmentIndex: number
        type: "move" | "resize-left" | "resize-right"
        startMouseX: number
        origStartFrac: number
        origEndFrac: number
      } | null,

      creating: null as {
        startDayIndex: number
        currentDayIndex: number
        startFrac: number
        currentFrac: number
      } | null,

      internalDays: [] as DaySchedule[],
    }
  },
  computed: {
    isIdle(): boolean {
      return !(this.creating || this.editing)
    },
    sortedDays(): DaySchedule[] {
      return this.internalDays.slice().sort((a, b) => (a.day < b.day ? -1 : 1))
    },
    segmentsContainerStyles(): Record<string, unknown> {
      const mainContainer = this.$refs.mainContainer?.getBoundingClientRect()
      if (!mainContainer || !this.segmentsContainerRect) {
        return {}
      }

      return {
        width: `${this.segmentsContainerRect.width}px`,
        height: `${this.segmentsContainerRect.height}px`,
        top: `${this.segmentsContainerRect.top - mainContainer.top}px`,
        left: `${this.segmentsContainerRect.left - mainContainer.left}px`,
      }
    },
    pixelsPerHour(): number {
      if (!this.segmentsContainerRect) return 0

      return this.segmentsContainerRect.width / 24
    },
  },
  watch: {
    days: {
      immediate: true,
      handler(newDays: DaySchedule[]) {
        this.internalDays = newDays.map((d) => ({
          day: d.day,
          segments: d.segments.map((s) => ({
            startTime: s.startTime,
            endTime: s.endTime,
          })),
        }))
      },
    },
    isIdle(isIdle) {
      if (isIdle) {
        this.mergeOverlappingSegments()
      }
    },
  },
  methods: {
    formatDay(day: DayCode): string {
      return new Intl.DateTimeFormat("en-US", {
        weekday: "short",
      }).format(new Date(0, 0, day + 1))
    },
    formatHour(hour: number): string {
      return (hour - 1).toString().padStart(2, "0") + "h"
    },
    parseTime(time: string): { hours: number; minutes: number } {
      const [H, M] = time.split(":").map((x) => parseInt(x, 10))

      return { hours: H, minutes: M }
    },
    padTime(frac: number): string {
      let totalMinutes = Math.round(frac * 60)
      if (totalMinutes < 0) totalMinutes = 0
      if (totalMinutes > 24 * 60) totalMinutes = 24 * 60
      const hh = Math.floor(totalMinutes / 60)
      const mm = totalMinutes % 60

      return `${hh.toString().padStart(2, "0")}:${mm
        .toString()
        .padStart(2, "0")}`
    },
    roundToFive(frac: number): number {
      const totalMins = frac * 60
      const snapped = Math.round(totalMins / 5) * 5

      return Math.max(0, Math.min(snapped, 24 * 60)) / 60
    },
    calculateBarStyle(
      dayIndex: number,
      startTime: string,
      endTime: string
    ): Record<string, string> {
      const { hours: sH, minutes: sM } = this.parseTime(startTime)
      const { hours: eH, minutes: eM } = this.parseTime(endTime)

      const startFrac = sH + sM / 60
      const endFrac = eH + eM / 60
      const durationFrac = endFrac - startFrac

      const leftPercent = (startFrac / 24) * 100
      const widthPercent = (durationFrac / 24) * 100

      const topPx = dayIndex * this.rowHeightPx
      const heightPx = this.rowHeightPx

      return {
        position: "absolute",
        top: `${topPx + 1}px`,
        left: `calc(${leftPercent}% + 1px)`,
        width: `calc(${widthPercent}% - 2px)`,
        height: `${heightPx - 2}px`,
      }
    },
    onResize() {
      const table = this.$refs.table as HTMLElement
      const cells = Array.from(
        table.querySelectorAll(".segment-cell")
      ) as HTMLElement[]
      if (!table || !cells.length) return

      const topLeftCell = cells[0].getBoundingClientRect()
      const bottomRightCell = cells[cells.length - 1].getBoundingClientRect()

      this.segmentsContainerRect = {
        top: topLeftCell.top,
        left: topLeftCell.left,
        width: bottomRightCell.right - topLeftCell.left,
        height: bottomRightCell.bottom - topLeftCell.top,
      }
    },
    onSegmentMouseDown(
      event: MouseEvent,
      dayIndex: number,
      segmentIndex: number
    ) {
      event.preventDefault()
      event.stopPropagation()
      if (!this.segmentsContainerRect) return

      const el = event.currentTarget as HTMLElement
      const rect = el.getBoundingClientRect()
      const offsetX = event.clientX - rect.left
      const edgeThreshold = 6

      let type: "move" | "resize-left" | "resize-right" = "move"
      if (offsetX < edgeThreshold) {
        type = "resize-left"
      } else if (offsetX > rect.width - edgeThreshold) {
        type = "resize-right"
      }

      const seg = this.sortedDays[dayIndex].segments[segmentIndex]
      const { hours: sH, minutes: sM } = this.parseTime(seg.startTime)
      const { hours: eH, minutes: eM } = this.parseTime(seg.endTime)
      const origStartFrac = sH + sM / 60
      const origEndFrac = eH + eM / 60

      this.editing = {
        dayIndex,
        segmentIndex,
        type,
        startMouseX: event.clientX,
        origStartFrac,
        origEndFrac,
      }

      document.addEventListener("mousemove", this.onMouseMove)
      document.addEventListener("mouseup", this.onMouseUp)
    },
    onMouseMove(e: MouseEvent) {
      if (!this.editing || !this.segmentsContainerRect) return
      e.preventDefault()

      const {
        dayIndex,
        segmentIndex,
        type,
        startMouseX,
        origStartFrac,
        origEndFrac,
      } = this.editing

      const deltaX = e.clientX - startMouseX
      const deltaHours = deltaX / this.pixelsPerHour

      let newStart = origStartFrac
      let newEnd = origEndFrac

      if (type === "move") {
        newStart = origStartFrac + deltaHours
        newEnd = origEndFrac + deltaHours
      } else if (type === "resize-left") {
        newStart = origStartFrac + deltaHours
      } else if (type === "resize-right") {
        newEnd = origEndFrac + deltaHours
      }

      newStart = Math.max(0, Math.min(newStart, 24))
      newEnd = Math.max(0, Math.min(newEnd, 24))

      if (newEnd <= newStart + 0.01) {
        if (type === "resize-left") {
          newStart = newEnd - 0.01
        } else if (type === "resize-right") {
          newEnd = newStart + 0.01
        } else {
          newStart = origStartFrac
          newEnd = origEndFrac
        }
      }

      newStart = this.roundToFive(newStart)
      newEnd = this.roundToFive(newEnd)

      const dayCode = this.sortedDays[dayIndex].day
      this.internalDays = this.internalDays.map((d) => {
        if (d.day !== dayCode) return d
        const newSegs = d.segments.map((s, idx) => {
          if (idx !== segmentIndex) return s

          return {
            startTime: this.padTime(newStart),
            endTime: this.padTime(newEnd),
          }
        })

        return { ...d, segments: newSegs }
      })
    },
    onMouseUp() {
      document.removeEventListener("mousemove", this.onMouseMove)
      document.removeEventListener("mouseup", this.onMouseUp)
      this.editing = null

      this.mergeOverlappingSegments()
    },
    onSegmentMouseMove(e: MouseEvent) {
      const el = e.currentTarget as HTMLElement
      const rect = el.getBoundingClientRect()
      const offsetX = e.clientX - rect.left
      const edgeThreshold = 6

      if (offsetX < edgeThreshold || offsetX > rect.width - edgeThreshold) {
        el.style.cursor = "ew-resize"
      } else {
        el.style.cursor = "grab"
      }
    },
    onSegmentMouseLeave(e: MouseEvent) {
      const el = e.currentTarget as HTMLElement
      el.style.cursor = "default"
    },
    deleteSegment(dayIndex: number, segmentIndex: number) {
      const dayCode = this.sortedDays[dayIndex].day
      this.internalDays = this.internalDays.map((d) => {
        if (d.day !== dayCode) return d
        const newSegs = d.segments.filter((_, idx) => idx !== segmentIndex)

        return { ...d, segments: newSegs }
      })
    },
    onBackgroundMouseDown(event: MouseEvent) {
      const clickedElement = event.target as HTMLElement
      if (clickedElement.closest(".segment")) {
        return
      }
      if (!this.segmentsContainerRect) return
      event.preventDefault()

      const y = event.clientY - this.segmentsContainerRect.top
      const clickedDayIndex = Math.floor(y / this.rowHeightPx)
      if (clickedDayIndex < 0 || clickedDayIndex >= this.sortedDays.length) {
        return
      }

      let startFrac =
        (event.clientX - this.segmentsContainerRect.left) / this.pixelsPerHour
      startFrac = Math.max(0, Math.min(startFrac, 24))

      this.creating = {
        startDayIndex: clickedDayIndex,
        currentDayIndex: clickedDayIndex,
        startFrac,
        currentFrac: startFrac,
      }

      document.addEventListener("mousemove", this.onCreateMouseMove)
      document.addEventListener("mouseup", this.onCreateMouseUp)
    },
    onCreateMouseMove(e: MouseEvent) {
      if (!this.creating || !this.segmentsContainerRect) return
      e.preventDefault()

      let frac =
        (e.clientX - this.segmentsContainerRect.left) / this.pixelsPerHour
      frac = Math.max(0, Math.min(frac, 24))
      this.creating.currentFrac = frac

      const y = e.clientY - this.segmentsContainerRect.top
      let newDayIndex = Math.floor(y / this.rowHeightPx)
      newDayIndex = Math.max(
        0,
        Math.min(newDayIndex, this.sortedDays.length - 1)
      )
      this.creating.currentDayIndex = newDayIndex
    },
    onCreateMouseUp() {
      if (!this.creating) return

      const { startDayIndex, currentDayIndex, startFrac, currentFrac } =
        this.creating

      let rawStart = Math.min(startFrac, currentFrac)
      let rawEnd = Math.max(startFrac, currentFrac)
      if (rawEnd - rawStart < 0.01) {
        this.cleanupCreate()

        return
      }
      const finalStart = this.roundToFive(rawStart)
      const finalEnd = this.roundToFive(rawEnd)

      const dayMin = Math.min(startDayIndex, currentDayIndex)
      const dayMax = Math.max(startDayIndex, currentDayIndex)

      const allDays = this.sortedDays.map((d) => d.day)
      const daysToAdd = allDays.slice(dayMin, dayMax + 1)

      this.internalDays = this.internalDays.map((d) => {
        if (!daysToAdd.includes(d.day)) return d

        return {
          ...d,
          segments: [
            ...d.segments,
            {
              startTime: this.padTime(finalStart),
              endTime: this.padTime(finalEnd),
            },
          ],
        }
      })

      this.cleanupCreate()

      this.mergeOverlappingSegments()
    },
    cleanupCreate() {
      document.removeEventListener("mousemove", this.onCreateMouseMove)
      document.removeEventListener("mouseup", this.onCreateMouseUp)
      this.creating = null
    },
    calculateMultiDayStyle(
      startIdx: number,
      endIdx: number,
      startFrac: number,
      endFrac: number
    ): Record<string, string> {
      const leftPercent = (Math.min(startFrac, endFrac) / 24) * 100
      const widthPercent =
        ((Math.max(startFrac, endFrac) - Math.min(startFrac, endFrac)) / 24) *
        100

      const topDay = Math.min(startIdx, endIdx)
      const bottomDay = Math.max(startIdx, endIdx)
      const topPx = topDay * this.rowHeightPx
      const heightPx = (bottomDay - topDay + 1) * this.rowHeightPx

      return {
        position: "absolute",
        top: `${topPx + 1}px`,
        left: `calc(${leftPercent}% + 1px)`,
        width: `calc(${widthPercent}% - 2px)`,
        height: `${heightPx - 2}px`,
      }
    },
    mergeOverlappingSegments() {
      this.internalDays = this.internalDays.map((dayObj) => {
        const intervals = dayObj.segments.map((s) => {
          const { hours: aH, minutes: aM } = this.parseTime(s.startTime)
          const { hours: bH, minutes: bM } = this.parseTime(s.endTime)

          return { start: aH + aM / 60, end: bH + bM / 60 }
        })
        intervals.sort((x, y) => x.start - y.start)
        const merged: { start: number; end: number }[] = []
        for (const iv of intervals) {
          if (!merged.length) {
            merged.push({ ...iv })
          } else {
            const last = merged[merged.length - 1]
            if (iv.start <= last.end + 1e-6) {
              last.end = Math.max(last.end, iv.end)
            } else {
              merged.push({ ...iv })
            }
          }
        }
        const newSegments: ScheduleSegment[] = merged.map((m) => ({
          startTime: this.padTime(this.roundToFive(m.start)),
          endTime: this.padTime(this.roundToFive(m.end)),
        }))

        return { day: dayObj.day, segments: newSegments }
      })
    },
  },
})
</script>

<style>
.schedule table {
  border-spacing: 0;
}
.segment {
  position: absolute;
}
.delete-btn {
  display: none;
}
.segment:hover .delete-btn {
  display: block;
}
</style>
