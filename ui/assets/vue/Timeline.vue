<template>
    <div>
        <svg class="e-w-full e-bg-gray-900" :height="xAxisHeight">
            <EXAxisOverview
                v-if="timeScale"
                :time-scale="timeScale"
                :height="xAxisHeight"
                :x="xAxisXPosition"
                :y="xAxisYPosition"
                :dark="true"
            />
        </svg>
    </div>
</template>

<script lang="ts">
import {defineComponent} from 'vue'
import * as d3 from "d3"

export default defineComponent({
    setup() {
        return {
            timeScale: d3.scaleTime()
                .domain([new Date(0, 0, 0, 0, 0), new Date(0, 0, 0, 23, 59)])
                .range([0, 800]),
            xAxisHeight: 22,
            xAxisXPosition: 0,
            xAxisYPosition: 0,
        }
    }
})
</script>