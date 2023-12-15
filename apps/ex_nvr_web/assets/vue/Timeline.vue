<template>
    <div>
        <ETimeline
            :events-groups="events"
            :tooltip-top="false"
            dark 
        >
            <template #tooltip="{ timestamp, active }">
                <div
                    v-if="active"
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
                        From : {{ new Date(event.startDate).toISOString() }} <br /> 
                        to : {{ new Date(event.endDate).toISOString() }}
                    </div>
                    <img :src="`/api/devices/${deviceId}/snapshot`" />
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
        events: {
            Recording: {
                label: "Recordings",
                color: "#FF5733",
                events: []
            },
        },
        deviceId: null
    }),
    mounted() {
        console.log("mounted")
        window.addEventListener("phx:update-timeline", this.updateEvents)
    },
    methods: {
        updateEvents(e) {
            this.events = e.detail.events
            this.deviceId = e.detail.device
        }
    }
}
</script>

<style scoped>

</style>