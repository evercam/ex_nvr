<template>
    <div>
        <ETimeline
            :events-groups="events"
            :tooltip-top="false"
            :showEventTooltip="false"
            dark 
            @event-mouseover="(event) => hoveredEvent = event"
            @event-mouseout="hoveredEvent = null"
        >
            <template #tooltip="{ timestamp, active }">
                <div
                    v-if="hoveredEvent && active"
                    class="e-rounded-lg e-p-5 e-m-2 e-text-black e-w-60"
                    :style="{ 
                        background: events[hoveredEvent.eventType].color,
                        transform: 'Translate(-50%)'
                    }"
                    >
                    <strong>{{ hoveredEvent.eventType }}: </strong>
                    <div v-if="hoveredEvent.eventData.startDate && hoveredEvent.eventData.endDate" class="e-text-xs">
                        From : {{ new Date(hoveredEvent.eventData.startDate).toISOString() }} <br /> 
                        to : {{ new Date(hoveredEvent.eventData.endDate).toISOString() }}
                    </div>
                    <img :src="`/api/devices/${deviceId}/snapshot?time=${new Date(timestamp).toISOString()}`" />
                </div>
                <div
                    v-else-if="active"
                    class="e-rounded-lg e-p-5 e-m-2 e-text-black e-w-60"
                    :style="{ 
                        background: '#374151',
                        transform: 'Translate(-50%)',
                        color: 'white'
                    }"
                >
                    {{ timestamp }}
                </div>
            </template>
            <template #eventTooltip="{ event, active, type }">
                
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
        events: {
            Recording: {
                label: "Recordings",
                color: "#FF5733",
                events: []
            },
        },
        deviceId: null,
        hoveredEvent: null
    }),
    mounted() {
        console.log("mounted")
        window.addEventListener("phx:update-timeline", this.updateEvents)
    },
    methods: {
        updateEvents(e) {
            console.log(e.detail)
            this.events = e.detail.events
            this.deviceId = e.detail.device
        },
    }
}
</script>

<style scoped>

</style>