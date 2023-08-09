defmodule ExNVR.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Accounts` context.
  """

  alias ExNVR.Accounts
  alias ExNVR.Accounts.UserToken
  alias Ecto.Changeset

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "Hello world!"
  def valid_first_name, do: "John"
  def valid_last_name, do: "Smith"
  def valid_language, do: Enum.random([:en])

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def valid_user_full_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      first_name: valid_first_name(),
      last_name: valid_last_name(),
      language: valid_language()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> ExNVR.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def valid_user_token(user, context) do
    case context do
      "access" ->
        with {_, user_access_token} <- UserToken.build_access_token(user) do
          Accounts.insert_user_token(user_access_token)
        end

      "session" ->
        with {_, user_session_token} <- UserToken.build_session_token(user) do
          Accounts.insert_user_token(user_session_token)
        end
    end
  end

  def expired_user_token(user, context) do
    case context do
      "access" ->
        with {_, user_access_token} <- UserToken.build_access_token(user) do
          Accounts.insert_user_token(user_access_token)
          |> Changeset.change(inserted_at: ~N[2022-08-03 09:53:05])
          |> Accounts.update_user_token()
        end

      "session" ->
        with {_, user_session_token} <- UserToken.build_session_token(user) do
          Accounts.insert_user_token(user_session_token)
          |> Changeset.change(inserted_at: ~N[2022-08-03 09:53:05])
          |> Accounts.update_user_token()
        end
    end
  end
end
