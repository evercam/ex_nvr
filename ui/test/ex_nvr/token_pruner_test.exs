defmodule ExNVR.TokenPrunerTest do
  use ExNVR.DataCase

  import ExNVR.AccountsFixtures

  alias ExNVR.Accounts
  alias ExNVR.Accounts.UserToken

  describe "Run delete_expired_tokens job" do
    test "delete_all_expired_tokens/0 deletes all expired tokens." do
      user = user_fixture()

      valid_token_1 = user_token_fixture(user, "access")
      valid_token_2 = user_token_fixture(user, "session")

      # expired tokens
      expired_token_1 = user_token_fixture(user, "access", ~N[2022-08-03 09:53:05])
      expired_token_2 = user_token_fixture(user, "session", ~N[2022-08-03 09:53:05])

      count = Repo.aggregate(UserToken, :count)

      Accounts.delete_all_expired_tokens()

      assert Repo.aggregate(UserToken, :count) == count - 2

      assert Repo.get(UserToken, valid_token_1.id)
      assert Repo.get(UserToken, valid_token_2.id)

      refute Repo.get(UserToken, expired_token_1.id)
      refute Repo.get(UserToken, expired_token_2.id)
    end
  end
end
