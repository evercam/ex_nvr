defmodule ExNVR.Activity.Actor do
  @moduledoc """
  Who performed an activity: a logged in user, an API client or the remote server.
  """

  alias ExNVR.Accounts.User

  @type type :: :user | :api | :remote

  @type t :: %__MODULE__{
          type: type(),
          id: String.t() | nil,
          label: String.t() | nil,
          ip: String.t() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, :id, :label, :ip]

  @doc """
  An actor for a logged in user acting from the web interface.

  Accepts an `:ip` option, either a string or an `:inet` address tuple.
  """
  @spec user(User.t(), Keyword.t()) :: t()
  def user(%User{} = user, opts \\ []), do: from_user(:user, user, opts)

  @doc """
  Same as `user/2` but for requests made through the REST API.
  """
  @spec api(User.t(), Keyword.t()) :: t()
  def api(%User{} = user, opts \\ []), do: from_user(:api, user, opts)

  @doc """
  The remote server ExNVR is connected to.
  """
  @spec remote(String.t()) :: t()
  def remote(label \\ "remote server"), do: %__MODULE__{type: :remote, label: label}

  @doc """
  An actor that couldn't be authenticated, e.g. a failed login. `label` is
  usually the email that was tried.
  """
  @spec anonymous(:user | :api, String.t() | nil, Keyword.t()) :: t()
  def anonymous(type, label, opts \\ []) when type in [:user, :api] do
    %__MODULE__{type: type, label: label && String.slice(label, 0, 160), ip: format_ip(opts[:ip])}
  end

  defp from_user(type, user, opts) do
    %__MODULE__{type: type, id: user.id, label: user.email, ip: format_ip(opts[:ip])}
  end

  defp format_ip(nil), do: nil
  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
end
