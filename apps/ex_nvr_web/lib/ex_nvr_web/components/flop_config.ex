defmodule ExNVRWeb.FlopConfig do
  import Phoenix.HTML.Tag

  def table_opts do
    [
      table_attrs: [
        class: "w-[40rem] mt-4 text-sm text-left sm:w-full text-gray-500 dark:text-gray-400"
      ],
      thead_attrs: [
        class: "text-xs text-black uppercase bg-blue-400 dark:bg-gray-700 dark:text-gray-400"
      ],
      thead_th_attrs: [class: "px-6 py-3 relative p-0 pb-2 text-center"],
      tbody_tr_attrs: [
        class:
          "text-black bg-gray-200 border-b dark:bg-gray-800 dark:border-gray-700 hover:bg-blue-200 dark:text-gray-400"
      ],
      tbody_td_attrs: [class: "relative w-14 p-0 p-4 text-center"],
      symbol_attrs: [class: "text-xl"],
      th_wrapper_attrs: [class: "flex items-center justify-center space-x-1"],
      no_results_content:
        content_tag(:p, "No results.",
          class: "px-6 py-3 w-[40rem] mt-4 text-xl text-left text-black dark:text-gray-400"
        )
    ]
  end
end
