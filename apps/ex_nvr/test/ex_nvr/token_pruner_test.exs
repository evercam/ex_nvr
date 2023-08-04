defmodule ExNVR.TokenPrunerTest do
  use ExNVR.DataCase

  import Ecto.Query
  import ExNVR.AccountsFixtures

  alias ExNVR.Accounts.UserToken
  alias ExNVR.TokenPruner

  describe "Run delete_expired_tokens job" do
    setup do
      user = user_fixture()

      valid_access = valid_user_token(user, "access")
      valid_session = valid_user_token(user, "session")

      expired_access = expired_user_token(user, "access")
      expired_session = expired_user_token(user, "session")

      %{
        expired_access: expired_access,
        expired_session: expired_session,
        valid_access: valid_access,
        valid_session: valid_session
      }
    end

    test "expired_tokens/1 returns the correct rows", %{
      expired_access: expired_access,
      expired_session: expired_session
    } do
      all_expired_tokens_query = UserToken.get_expired_tokens()

      count_rows =
        from(all_expired_tokens_query, select: count())
        |> Repo.one()

      assert count_rows == 2

      assert Repo.exists?(from t in all_expired_tokens_query, where: t.id == ^expired_session.id)
      assert Repo.exists?(from t in all_expired_tokens_query, where: t.id == ^expired_access.id)
    end

    test "delete_all_expired_tokens/0 deletes all expired tokens.", %{
      valid_access: valid_access,
      valid_session: valid_session
    } do
      TokenPruner.prune_expired_tokens()

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
