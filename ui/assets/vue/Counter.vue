<script lang="ts">
import {defineComponent} from 'vue'
import {ETimeline} from '@evercam/ui/vue3'

export default defineComponent({
  name: 'TimelineWrapper',
  components: {
    ETimeline
  },
  setup() {
    const eventsGroups = {
      Group1: {
        label: "Group 1",
        color: "#eee",
        events: [
          {
            startDate: new Date("2022-12-10T00:00:00").getTime(),
            endDate: new Date("2022-12-15T01:00:00").getTime(),
            color: "#5f6b43",
            text: "Holiday",
          },
          {
            startDate: new Date("2023-01-01T00:00:00").getTime(),
            endDate: new Date("2023-03-01T00:00:00").getTime(),
            color: "#5f6b43",
            text: "Q1 2023: Lorem Ipsum.",
          },
          {
            startDate: new Date("2023-04-01T00:00:00").getTime(),
            endDate: new Date("2023-06-10T00:00:00").getTime(),
            color: "rgb(144,103,229)",
            text: "Q2-Q3 2023: April to mid June.",
          },
          {
            startDate: new Date("2023-07-10T00:00:00").getTime(),
            endDate: new Date("2023-08-01T00:00:00").getTime(),
            color: "rgb(62,129,112)",
            text: "Q3",
          },
          {
            startDate: new Date("2023-09-01T00:00:00").getTime(),
            endDate: new Date("2023-10-10T00:00:00").getTime(),
            color: "#d35d30",
            text: "Q4 2023",
          },
          {
            startDate: new Date("2023-10-20T00:00:00").getTime(),
            endDate: new Date("2023-11-05T00:00:00").getTime(),
            color: "#d35d30",
            text: "Holiday",
          },
        ],
      },
      Group2: {
        label: "Group 2",
        color: "#eee",
        events: [
          {
            startDate: new Date("2023-02-01T00:00:00").getTime(),
            endDate: new Date("2023-04-01T00:00:00").getTime(),
            color: "#5f6b43",
            text: "Q1-Q2 2023: Lorem ipsum dolor.",
          },
          {
            startDate: new Date("2023-04-15T00:00:00").getTime(),
            endDate: new Date("2023-06-01T00:00:00").getTime(),
            color: "rgb(144,103,229)",
            text: "Q2 2023.",
          },
          {
            startDate: new Date("2023-07-01T00:00:00").getTime(),
            endDate: new Date("2023-08-20T00:00:00").getTime(),
            color: "rgb(62,129,112)",
            text: "Q3 2023.",
          },
          {
            startDate: new Date("2023-09-10T00:00:00").getTime(),
            endDate: new Date("2023-10-05T00:00:00").getTime(),
            color: "#d35d30",
            text: "Q4 2023",
          },
        ],
      },
      Milestones: {
        label: "",
        color: "#d35d30",
        chartType: "milestones",
        height: 80,
        events: [
          {
            milestoneType: "drone",
            timestamp: new Date("2023-01-01T00:00:00").getTime(),
            text: "Test",
            size: 32,
          },
          {
            milestoneType: "test",
            timestamp: new Date("2023-02-14T00:00:00").getTime(),
            text: "Sample text",
          },
          {
            milestoneType: "test",
            timestamp: new Date("2023-03-08T00:00:00").getTime(),
            text: "Longer sample text",
          },
        ],
      },
      Milestones2: {
        label: "",
        color: "rgba(2,122,205,0.6)",
        chartType: "milestones",
        height: 60,
        dots: true,
        events: [
          {
            milestoneType: "drone",
            timestamp: new Date("2023-02-01T00:00:00").getTime(),
            text: "Test",
            size: 32,
          },
          {
            milestoneType: "test",
            timestamp: new Date("2023-04-14T00:00:00").getTime(),
            text: "Sample text",
          },
          {
            milestoneType: "test",
            timestamp: new Date("2023-06-08T00:00:00").getTime(),
            text: "Longer sample text",
          },
        ],
      },
    }

    return {
      eventsGroups
    }
  }
})
</script>

<template>
  <div class="timeline-container" style="width: 1000px;">
    <ETimeline
        :events-groups="eventsGroups"
        :bar-height="35"
        :bar-y-padding="5"
        min-date="2021-01-15"
        max-date="2025-10-15"
        dark
    />
  </div>
</template>

<style scoped>
.timeline-container {
  clip-path: inset(-100px 0px 0px 0px);
}
</style>