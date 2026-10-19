defmodule ExNVRWeb.Components.Settings do
  @moduledoc false

  use Phoenix.Component

  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :footer

  def settings_section(assigns) do
    ~H"""
    <div class="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden">
      <div class="px-5 py-3.5 border-b border-gray-200 dark:border-gray-700">
        <h3 class="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-widest">
          {@title}
        </h3>
      </div>
      <div class="divide-y divide-gray-100 dark:divide-gray-700">
        {render_slot(@inner_block)}
      </div>
      <div
        :if={@footer != []}
        class="px-5 py-3 border-t border-gray-100 dark:border-gray-700 flex items-center justify-between"
      >
        {render_slot(@footer)}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block, required: true

  def settings_row(assigns) do
    ~H"""
    <div class="px-5 py-4 flex flex-col sm:flex-row sm:items-start gap-3 sm:gap-8">
      <div class="sm:w-56 shrink-0">
        <p class="text-sm font-medium text-gray-700 dark:text-gray-300">{@label}</p>
        <p :if={@description} class="text-xs text-gray-400 dark:text-gray-500 mt-0.5">
          {@description}
        </p>
      </div>
      <div class="flex-1 min-w-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
