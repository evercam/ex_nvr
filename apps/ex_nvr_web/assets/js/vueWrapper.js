import Vue from "vue"

export default function vueWrapper({ el, component, data = {} }) {
  return new Vue({
    el: el,
    render: (h) => h(component, data)
  })
}