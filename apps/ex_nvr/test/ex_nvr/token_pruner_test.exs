defmodule ExNVR.TokenPrunerTest do
  use ExNVR.DataCase

  import Ecto.Query
  import ExNVR.AccountsFixtures

  alias ExNVR.Accounts
  alias ExNVR.Accounts.UserToken

  describe "Run delete_expired_tokens job" do
    setup do
      user = user_fixture()

      valid_access = user_token(user, "access")
      valid_session = user_token(user, "session")

      # expired tokens
      user_token(user, "access", ~N[2022-08-03 09:53:05])
      user_token(user, "session", ~N[2022-08-03 09:53:05])

      %{
        valid_access: valid_access,
        valid_session: valid_session
      }
    end

    test "delete_all_expired_tokens/0 deletes all expired tokens.", %{
      valid_access: valid_access,
      valid_session: valid_session
    } do
      Accounts.delete_all_expired_tokens()

      current_tokens_query = from(t in UserToken)

      count_rows =
        from(current_tokens_query, select: count())
        |> Repo.one()

      assert count_rows == 2

      assert Repo.exists?(from t in current_tokens_query, where: t.id == ^valid_access.id)
      assert Repo.exists?(from t in current_tokens_query, where: t.id == ^valid_session.id)
    end
  end
end
