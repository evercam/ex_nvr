defmodule ExNVR.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `ExNVR.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "Hello world!"
  def valid_first_name, do: "test_first_name#{:rand.uniform(999999)}"
  def valid_last_name, do: "test_last_name#{:rand.uniform(999999)}"
  def valid_username, do: "test_username#{:rand.uniform(999999)}"
  def valid_language, do: Enum.random([:en, :fr])

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      first_name: valid_first_name(),
      last_name: valid_last_name()
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
end
