defmodule ExNVR.TokenPrunerTest do
  alias Membrane.HTTPAdaptiveStream.Manifest.Changeset
  use ExNVR.DataCase

  import Ecto.Query
  import ExNVR.AccountsFixtures

  alias ExNVR.Accounts.UserToken
  alias ExNVR.TokenPruner
  alias Ecto.Changeset

  describe "Run delete_expired_tokens job" do
    setup do
      user = user_fixture()

      # Create valid access token
      {_, user_access_token} = UserToken.build_access_token(user)
      {:ok, valid_access} = Repo.insert(user_access_token)

      # Create valid session token
      {_, user_session_token} = UserToken.build_session_token(user)
      {:ok, valid_session} = Repo.insert(user_session_token)

      # Create expired access token
      {_, user_expired_access_token} = UserToken.build_access_token(user)
      {:ok, inserted_token} = Repo.insert(user_expired_access_token)

      {:ok, expired_access} =
        inserted_token
        |> Changeset.change(inserted_at: ~N[2022-08-03 09:53:05])
        |> Repo.update()

      # Create expired session token
      {_, user_expired_session_token} = UserToken.build_session_token(user)
      {:ok, inserted_token} = Repo.insert(user_expired_session_token)

      {:ok, expired_session} =
        inserted_token
        |> Changeset.change(inserted_at: ~N[2022-08-02 09:53:05])
        |> Repo.update()

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
