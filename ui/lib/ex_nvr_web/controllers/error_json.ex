defmodule ExNVRWeb.ErrorJSON do
  # If you want to customize a particular status code,
  # you may add your own clauses, such as:

  def render("404.json", assigns) do
    msg = assigns[:message] || "not found"
    %{message: msg}
  end

  def render("401.json", _assigns) do
    %{message: "unauthorized"}
  end

  def render("403.json", _assigns) do
    %{message: "Forbidden"}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
