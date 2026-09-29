defmodule ExNVR.RemoteStorageTest do
  use ExUnit.Case, async: true

  alias ExNVR.RemoteStorage

  defp changeset(bucket) do
    RemoteStorage.create_changeset(%{
      name: "storage",
      type: :s3,
      s3_config: %{bucket: bucket, access_key_id: "key", secret_access_key: "secret"}
    })
  end

  defp bucket_error(changeset) do
    case changeset.changes.s3_config.errors[:bucket] do
      {message, _opts} -> message
      nil -> nil
    end
  end

  test "accepts plain bucket names, trimming surrounding spaces" do
    for input <- ["my-bucket", "logs.example.com", " my-bucket "] do
      changeset = changeset(input)
      assert changeset.valid?, input
      assert changeset.changes.s3_config.changes.bucket == String.trim(input)
    end
  end

  test "rejects URLs, ARNs and paths, saying what to enter instead" do
    assert bucket_error(changeset("s3://my-bucket")) ==
             ~s(remove the "s3://" prefix, enter the bucket name only)

    assert bucket_error(changeset("https://my-bucket.s3.amazonaws.com")) ==
             ~s(remove the "https://" prefix, enter the bucket name only)

    assert bucket_error(changeset("arn:aws:s3:::my-bucket")) ==
             "enter the bucket name, not its ARN"

    for input <- ["my-bucket/", "my-bucket/footage"] do
      assert bucket_error(changeset(input)) ==
               "enter the bucket name only, without slashes or folders"
    end
  end

  test "rejects names S3 would refuse" do
    for input <- ["My_Bucket", "ab", "-bucket"] do
      assert bucket_error(changeset(input)) ==
               "must be 3-63 lowercase letters, digits, dots or dashes",
             input
    end
  end
end
