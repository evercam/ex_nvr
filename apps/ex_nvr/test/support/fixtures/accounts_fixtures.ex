defmodule ExNVR.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Accounts` context.
  """

  alias ExNVR.Accounts.UserToken
  alias ExNVR.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "Hello world!"
  def valid_first_name, do: "John"
  def valid_last_name, do: "Smith"
  def valid_language, do: Enum.random([:en])
  def valid_role, do: :admin

  @spec valid_user_attributes(map()) :: map()
  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  @spec valid_user_full_attributes(map()) :: map()
  def valid_user_full_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      first_name: valid_first_name(),
      last_name: valid_last_name(),
      language: valid_language(),
      role: valid_role()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_full_attributes()
      |> ExNVR.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def user_token_fixture(user, context, inserted_at \\ nil) do
    {_token, user_token} =
      if context == "session" do
        UserToken.build_session_token(user)
      else
        UserToken.build_access_token(user)
      end

    user_token = %UserToken{
      user_token
      | inserted_at: inserted_at
    }

    Repo.insert!(user_token)
  end
end
