defmodule ExNVRWeb.FlopConfig do
  def table_opts do
    [
      table_attrs: [
        class: "w-[40rem] mt-4 text-sm text-left sm:w-full text-gray-500 dark:text-gray-400"
      ],
      thead_attrs: [
        class: "text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400"
      ],
      thead_th_attrs: [class: "px-6 py-3 relative p-0 pb-2"],
      tbody_tr_attrs: [
        class: "bg-white border-b dark:bg-gray-800 dark:border-gray-700 hover:bg-gray-50"
      ],
      tbody_td_attrs: [class: "relative w-14 p-0 p-4"],
      symbol_attrs: [class: "text-xl"]
    ]
  end
end
