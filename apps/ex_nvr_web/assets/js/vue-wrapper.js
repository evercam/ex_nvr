import Vue from "vue"

export function renderVueComponent({ el, component, props, events }) {
  return new Vue({
    el: el,
    render: (h) => h(component, { props, on: events})
  })
}