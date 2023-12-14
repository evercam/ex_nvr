<template>
    <div>
        <ETimeline
            :selected-timestamp="selectedTimeStamp"
            :events-groups="events"
            :tooltip-top="false"
            dark 
        >
            <template #eventTooltip="{ event, active, type }">
                <div
                    v-if="event && active"
                    class="e-rounded-lg e-p-5 e-m-2 e-text-black e-w-60"
                    :style="{ 
                        background: events[type].color,
                        transform: 'Translate(-50%)'
                    }"
                    >
                    <strong>{{ type }}: </strong>
                    <div v-if="event.startDate && event.endDate" class="e-text-xs">
                        From : {{ new Date(event.startDate).toISOString() }}
                    </div>
                </div>
            </template>
        </ETimeline>
    </div>
</template>

<script>
import { ETimeline } from "@evercam/ui"

export default {
    components: {
        ETimeline
    },
    data: () => ({
        selectedTimeStamp: null,
        events: {
            Recording: {
                label: "Recordings",
                color: "#FF5733",
                events: []
            },
        }
    }),
    mounted() {
        window.addEventListener("phx:update-timeline", this.updateEvents)
    },
    methods: {
        updateEvents(e) {
            this.events = e.detail.events
        }
    }
}
</script>

<style scoped>

</style>