defmodule ExNVRWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At the first glance, this module may seem daunting, but its goal is
  to provide some core building blocks in your application, such modals,
  tables, and forms. The components are mostly markup and well documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Gettext, backend: ExNVRWeb.Gettext
  use Phoenix.Component

  alias ExNVRWeb.Components
  alias Phoenix.HTML
  alias Phoenix.LiveView.JS

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        This is a modal.
      </.modal>

  JS commands may be passed to the `:on_cancel` to configure
  the closing/cancel event, for example:

      <.modal id="confirm" on_cancel={JS.navigate(~p"/posts")}>
        This is another modal.
      </.modal>

  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="fixed top-0 left-0 right-0 z-50 hidden w-full p-4 overflow-x-hidden overflow-y-auto md:inset-0 h-[calc(100%-1rem)] max-h-full justify-center"
    >
      <div id={"#{@id}-bg"} class="bg-zinc-50/90 fixed inset-0 transition-opacity" aria-hidden="true" />
      <div
        class={["fixed inset-0 overflow-y-auto", @class || "dark:bg-gray-400"]}
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-lg p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-lg bg-gray-300 p-2 shadow-lg ring-1 transition shadow dark:bg-gray-800"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("data-cancel", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  <.icon name="hero-x-mark-solid dark:bg-white" class="h-5 w-5" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :header, required: true
  slot :inner_block, required: true

  def modal2(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      tabindex="-1"
      aria-hidden="true"
      class="hidden overflow-y-auto overflow-x-hidden fixed top-0 right-0 left-0 z-50 justify-center items-center w-full md:inset-0 h-[calc(100%-1rem)] max-h-full"
    >
      <div class="relative p-4 w-full max-w-md max-h-full">
        <!-- Modal content -->
        <div class="relative bg-white rounded-lg shadow-sm dark:bg-gray-700">
          <!-- Modal header -->
          <div class="flex items-center justify-between p-4 md:p-5 border-b rounded-t dark:border-gray-600 border-gray-200">
            <h3 class="text-xl font-semibold text-gray-900 dark:text-white">
              {render_slot(@header)}
            </h3>
            <button
              type="button"
              class="end-2.5 text-gray-400 bg-transparent hover:bg-gray-200 hover:text-gray-900 rounded-lg text-sm w-8 h-8 ms-auto inline-flex justify-center items-center dark:hover:bg-gray-600 dark:hover:text-white"
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
            >
              <.icon name="hero-x-mark-solid dark:bg-white" class="h-5 w-5" />
              <span class="sr-only">Close modal</span>
            </button>
          </div>
          <!-- Modal body -->
          <div class="p-4 md:p-5">
            {render_slot(@inner_block)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-2 right-5 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info &&
          "text-sm text-blue-800 rounded-lg bg-blue-50 dark:bg-gray-800 dark:text-blue-400",
        @kind == :error &&
          "text-sm text-red-800 rounded-lg bg-red-50 dark:bg-gray-800 dark:text-red-400"
      ]}
      {@rest}
    >
      <p
        :if={@title}
        class="flex items-center gap-1.5 text-sm font-semibold leading-6 dark:bg-gray-800"
      >
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        {@title}
      </p>
      <p class="mt-2 text-sm leading-5">{msg}</p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title="Success!" flash={@flash} />
    <.flash kind={:error} title="Error!" flash={@flash} />
    <.flash
      id="disconnected"
      kind={:error}
      title="We can't find the internet"
      phx-disconnected={show("#disconnected")}
      phx-connected={hide("#disconnected")}
      hidden
    >
      Attempting to reconnect <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a submit button"
  attr :actions_class, :string, default: ""

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-4">
        {render_slot(@inner_block, f)}
        <div :for={action <- @actions} class={"mt-2 flex items-center gap-6 " <> @actions_class}>
          {render_slot(action, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """

  attr :type, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form name value)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium",
        "ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        "focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4",
        "[&_svg]:shrink-0 text-primary-foreground h-10 px-4 py-2 bg-blue-600 hover:bg-blue-700 dark:text-white",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `%Phoenix.HTML.Form{}` and field name may be passed to the input
  to build input names and error messages, or all the attributes and
  errors may be passed explicitly.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
               range radio search select tel text textarea time url week toggle)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"

  attr :rest, :global,
    include: ~w(autocomplete cols disabled form list max maxlength min minlength
                pattern placeholder readonly required rows size step)

  slot :inner_block

  def input(%{field: %HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "toggle", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="inline-flex items-center mb-5 cursor-pointer">
        <input type="hidden" name={@name} value="false" />
        <input
          id={@id}
          type="checkbox"
          name={@name}
          value="true"
          checked={@checked}
          class="sr-only peer"
          {@rest}
        />
        <div class="relative w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:w-5 after:h-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600 dark:peer-checked:bg-blue-600">
        </div>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-black dark:text-white">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={[
            "rounded text-black border-gray-300 rounded bg-gray-50 focus:ring-3 focus:ring-blue-300",
            "dark:bg-gray-700 dark:border-gray-600 dark:focus:ring-blue-600",
            "dark:ring-offset-gray-800 dark:focus:ring-offset-gray-80"
          ]}
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "radio", options: nil} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600 dark:text-white">
        <input
          type="radio"
          id={@id}
          name={@name}
          class={[
            "rounded text-zinc-900 border-gray-300 rounded bg-gray-50 focus:ring-3 focus:ring-blue-300",
            "dark:bg-gray-700 dark:border-gray-600 dark:focus:ring-blue-600",
            "dark:ring-offset-gray-800 dark:focus:ring-offset-gray-80"
          ]}
          value={@value}
          checked={@checked}
          {@rest}
        />
        {@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "radio"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <ul class="border border-gray-200 rounded-lg dark:border-gray-600">
        <li
          :for={option <- @options}
          class="p-2 w-full border-b border-gray-200 rounded-t-lg dark:border-gray-600"
        >
          <div class="flex items-center ps-3">
            <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600 dark:text-white">
              <input
                type="radio"
                id={@id}
                name={@name}
                class={[
                  "rounded text-zinc-900 border-gray-300 rounded bg-gray-50 focus:ring-3 focus:ring-blue-300",
                  "dark:bg-gray-700 dark:border-gray-600 dark:focus:ring-blue-600",
                  "dark:ring-offset-gray-800 dark:focus:ring-offset-gray-80"
                ]}
                value={elem(option, 0)}
                checked={elem(option, 0) == @value}
                {@rest}
              />
              {@label}
            </label>
            {render_slot(@inner_block, option)}
          </div>
        </li>
      </ul>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "range"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600 dark:text-white">
        <input
          type="range"
          id={@id}
          name={@name}
          class={[
            "rounded text-zinc-900 border-gray-300 rounded bg-gray-50 focus:ring-3 focus:ring-blue-300",
            "dark:bg-gray-700 dark:border-gray-600 dark:focus:ring-blue-600",
            "dark:ring-offset-gray-800 dark:focus:ring-offset-gray-80 w-60"
          ]}
          value={@value}
          {@rest}
        />
        {"(#{@value}%) #{@label}"}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <select
        id={@id}
        name={@name}
        class={[
          "mt-1 block w-full rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 text-sm",
          "dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "mt-2 block w-full rounded-lg text-zinc-900 focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "min-h-[6rem] border-zinc-300 focus:border-zinc-400 dark:bg-gray-700",
          "dark:border-gray-600 dark:placeholder-gray-400 dark:text-white",
          "dark:focus:ring-blue-500 dark:focus:border-blue-500",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label for={@id}>{@label}</.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "mt-1 block w-full rounded-lg text-black focus:ring-0 sm:text-sm sm:leading-6",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "border-zinc-300 focus:border-zinc-400 dark:bg-gray-600 dark:border-gray-500",
          "dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500",
          "text-black",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr :for, :string, default: nil
  slot :inner_block, required: true

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-black dark:text-white">
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-3 flex gap-3 text-sm leading-6 text-rose-600 phx-no-feedback:hidden">
      <.icon name="hero-exclamation-circle-mini" class="mt-0.5 h-5 w-5 flex-none" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800 dark:text-white">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600 dark:text-white">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-4 text-sm text-left sm:w-full text-gray-500 dark:text-gray-400">
        <thead class="text-xs text-black uppercase bg-blue-400 dark:bg-gray-700 dark:text-gray-400">
          <tr>
            <th :for={col <- @col} class="px-6 py-3">{col[:label]}</th>
            <th class="relative p-0 pb-4"><span class="sr-only">{gettext("Actions")}</span></th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}>
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="text-black bg-gray-200 border-b dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400"
          >
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={[i == 0 && "p-4", i != 0 && "px-6 py-4", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block">
                <span class="absolute group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative"]}>
                  {render_slot(col, @row_item.(row))}
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div>
                <span :for={action <- @action}>
                  {render_slot(action, @row_item.(row))}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500">{item.title}</dt>
          <dd class="text-zinc-700">{render_slot(item)}</dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr :navigate, :any, required: true
  slot :inner_block, required: true

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        {render_slot(@inner_block)}
      </.link>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.card>
        <p>Hello World</p>
      </.card>
  """
  attr :class, :any, default: "", doc: "the classes names to append"

  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={@class <> " p-4 bg-gray-300 border border-gray-500 rounded-lg shadow sm:p-6 md:p-8 dark:bg-gray-800 dark:border-gray-700"}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  slot :inner_block, required: true

  def tag(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center dark:bg-gray-200 rounded-full border px-2.5 py-0.5 font-semibold transition-colors",
      "focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 border-transparent bg-gray-200 hover:bg-primary/80",
      "text-xs dark:text-black"
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  def pagination(assigns) do
    ~H"""
    <div aria-label="Pagination" class="flex justify-end mt-4">
      <ul :if={@meta.total_pages > 0} class="flex items-center -space-x-px h-8 text-sm">
        <li>
          <a
            href="#"
            phx-click="paginate"
            phx-value-page={@meta.previous_page}
            class={
              [
                "flex items-center justify-center px-3 h-8 ml-0 leading-tight bg-white border border-gray-300 rounded-l-lg"
              ] ++
                if not @meta.has_previous_page?,
                  do: ["pointer-events-none text-gray-300"],
                  else: [
                    "text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                  ]
            }
          >
            <span class="sr-only">Previous</span>
            <.icon name="hero-chevron-left" class="w-4 h-4" />
          </a>
        </li>
        <li :for={page <- 1..2} :if={@meta.total_pages > 6}>
          <.pagination_link current_page={@meta.current_page} page={page} />
        </li>
        <li :if={@meta.total_pages > 6 && @meta.current_page > 4}>
          <span class="px-3 h-8 text-gray-500">...</span>
        </li>
        <li
          :for={idx <- 3..(@meta.total_pages - 2)//1}
          :if={@meta.total_pages > 6 && abs(@meta.current_page - idx) <= 1}
        >
          <.pagination_link current_page={@meta.current_page} page={idx} target={assigns[:target]} />
        </li>
        <li :if={@meta.total_pages > 6 && @meta.current_page < @meta.total_pages - 3}>
          <span class="px-3 h-8 text-gray-500">...</span>
        </li>
        <li :for={page <- [@meta.total_pages - 1, @meta.total_pages]} :if={@meta.total_pages > 6}>
          <.pagination_link current_page={@meta.current_page} page={page} target={assigns[:target]} />
        </li>
        <li :for={idx <- 1..@meta.total_pages} :if={@meta.total_pages <= 6}>
          <.pagination_link current_page={@meta.current_page} page={idx} target={assigns[:target]} />
        </li>
        <li>
          <a
            href="#"
            phx-click="paginate"
            phx-target={assigns[:target]}
            phx-value-page={@meta.next_page}
            class={
              [
                "flex items-center justify-center px-3 h-8 leading-tight border border-gray-300 bg-white rounded-r-lg"
              ] ++
                if not @meta.has_next_page?,
                  do: ["pointer-events-none text-gray-300"],
                  else: [
                    "text-gray-500 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
                  ]
            }
          >
            <span class="sr-only">Next</span>
            <.icon name="hero-chevron-right" class="w-4 h-4" />
          </a>
        </li>
      </ul>
    </div>
    """
  end

  defp pagination_link(assigns) do
    ~H"""
    <.link
      href="#"
      phx-click="paginate"
      phx-target={assigns[:target]}
      phx-value-page={@page}
      class={
        [
          "flex items-center justify-center px-3 h-8 leading-tight border dark:border-gray-700"
        ] ++
          if @current_page == @page,
            do: [
              "z-10 pointer-events-none text-blue-600 bg-blue-50 border-blue-300 hover:bg-blue-100 hover:text-blue-700 dark:bg-gray-700 dark:text-white"
            ],
            else: [
              "text-gray-500 bg-white border-gray-300 hover:bg-gray-100 hover:text-gray-700 dark:bg-gray-800 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
            ]
      }
    >
      {@page}
    </.link>
    """
  end

  attr :class, :string, default: ""

  def separator(assigns) do
    ~H"""
    <hr class={["h-px my-8 bg-gray-200 border-0 dark:bg-gray-700", @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def show_modal2(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(
      to: "##{id}",
      display: "flex",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  def hide_modal2(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
  end

  attr :dropdown_id, :string, required: true
  attr :rest, :global

  def three_dot(assigns) do
    ~H"""
    <button
      data-dropdown-toggle={@dropdown_id}
      class="text-sm ml-3 bg-gray-200 hover:bg-gray-200 text-zinc-900 dark:bg-gray-800 dark:text-gray-400"
      {@rest}
    >
      <.icon name="hero-ellipsis-vertical" class="w-6 h-6" />
    </button>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ExNVRWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ExNVRWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  attr :target, :string

  def copy_button(assigns) do
    ~H"""
    <button
      class="bg-gray-700 hover:bg-slate-600 text-white font-bold py-2 px-3 rounded-md"
      phx-click={JS.dispatch("events:clipboard-copy", to: "#{@target}")}
      title="Copy to clipboard"
    >
      <.icon name="hero-document-duplicate" class="copy-icon" />
      <.icon name="hero-check" class="copied-icon hidden" />
    </button>
    """
  end

  slot :actions
  attr :id, :string
  attr :code, :string
  attr :lang, :string
  attr :copy_target, :string, required: false

  def code_snippet(assigns) do
    ~H"""
    <div class="relative h-full">
      <div
        id={@id}
        phx-hook="HighlightSyntax"
        data-lang={@lang}
        class="relative bg-gray-100 dark:bg-gray-800 rounded-md overflow-x-auto border border-white dark:bg-gray-800 dark:border-gray-700"
      >
        <pre class="text-sm text-gray-400 p-5"><code><%= @code %></code></pre>
      </div>

      <div class="absolute top-3 right-3 gap-2">
        <.copy_button target={if assigns[:copy_target], do: assigns[:copy_target], else: "##{@id}"} />
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  defdelegate sidebar(assigns), to: Components.Sidebar

  defdelegate tabs(assigns), to: Components.Tabs

  defdelegate icon(assigns), to: Components.Icon
end
