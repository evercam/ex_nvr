import * as d3 from "d3"

const DAY = 86_400_000
let timelineState = {}

function drawSegments(svg, segments, x) {
    svg.selectAll("rect").remove()
    segments.forEach(({ start_date, end_date }) => {
        svg
            .append("rect")
            .datum({ start_date, end_date })
            .attr("x", x(start_date))
            .attr("y", 0)
            .attr("width", x(end_date) - x(start_date))
            .attr("height", 27.5)
            .style("fill", "#4dc007")
    })
}

export function updateTimelineSegments(element) {
    const segments = JSON.parse(element.dataset.segments).map(
        ({ start_date, end_date }) => ({
            start_date: new Date(start_date),
            end_date: new Date(end_date),
        })
    )

    drawSegments(timelineState.svg, segments, timelineState.x)
}

export default function createTimeline(element) {
    let isMouseDown = false
    const timeline = element.querySelector("#timeline")
    const tooltip = element.querySelector("#tooltip")
    const cursor = element.querySelector("#cursor")
    const width = timeline.offsetWidth
    const segments = JSON.parse(element.dataset.segments).map(
        ({ start_date, end_date }) => ({
            start_date: new Date(start_date),
            end_date: new Date(end_date),
        })
    )

    const [defaultMinDate, defaultMaxDate] = [
        new Date(new Date().getTime() - DAY),
        new Date(),
    ]
    const x = d3
        .scaleTime()
        .domain([
            d3.min(
                [...segments, { start_date: defaultMinDate }],
                (d) => d.start_date
            ),
            d3.max([...segments, { end_date: defaultMaxDate }], (d) => d.end_date),
        ])
        .range([0, width])
    timelineState.x = x
    const x2 = x.copy()

    const xAxis = d3
        .axisBottom(x)
        .ticks(5)
        .tickSize(10)
        .tickPadding(5)
        .tickFormat(d3.timeFormat("%Y-%m-%d %H:%M:%S"))

    const handleZoom = (event) => {
        const rescaledX = event.transform.rescaleX(x2)
        x.domain(rescaledX.domain())
        svg.select(".x-axis").call(xAxis.scale(rescaledX))
        svg
            .selectAll("rect")
            .attr("x", (d) => x(d.start_date))
            .attr("width", (d) => x(d.end_date) - x(d.start_date))

        svg.select(".x-axis").call(d3.axisBottom(x).ticks(10))
    }

    const svg = d3
        .select(timeline)
        .append("svg")
        .attr("width", width)
        .attr("height", 100)
        .call(d3.zoom().on("zoom", handleZoom).scaleExtent([1, 50]))
    timelineState.svg = svg

    updateTimelineSegments(element)

    svg
        .append("g")
        .attr("class", "x-axis")
        .attr("transform", "translate(0,27.5)")
        .call(xAxis)

    svg.on("mousedown", function () {
        isMouseDown = true
    })

    document.addEventListener("mouseup", () => {
        isMouseDown = false
    })

    svg.on("mousemove", function (event) {
        if (isMouseDown) {
            return
        }
        tooltip.classList.remove("hidden")
        cursor.classList.remove("hidden")
        const [mouseX, mouseY] = d3.pointer(event, this)
        const date = x.invert(mouseX)
        tooltip.textContent = d3.timeFormat("%Y-%m-%d %H:%M")(date)
        tooltip.style.left =
            mouseX - tooltip.getBoundingClientRect().width / 2 + "px"
        tooltip.style.top = 50 + "px"
        cursor.style.left = mouseX + "px"
    })

    svg.on("click", function (event) {
        const [mouseX, _] = d3.pointer(event, this)
        const date = x.invert(mouseX)
        const formatter = new Intl.DateTimeFormat("en", {
            year: "numeric",
            month: "2-digit",
            day: "2-digit",
            hour: "2-digit",
            minute: "2-digit",
            hour12: false,
        })
        const dateFormatted = formatter.formatToParts(date)
        const datePart = `${dateFormatted[4].value}-${dateFormatted[0].value}-${dateFormatted[2].value}`
        const timePart = `${dateFormatted[6].value}:${dateFormatted[8].value}:00`

        window.TimelineHook.pushEvent("datetime", {
            value: `${datePart}T${timePart}`,
        })
    })

    svg.on("mouseleave", () => {
        tooltip.classList.add("hidden")
        cursor.classList.add("hidden")
    })
}
