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

  test "rejects URLs, ARNs, paths and names S3 would refuse" do
    for input <- [
          "s3://my-bucket",
          "https://my-bucket.s3.amazonaws.com",
          "arn:aws:s3:::my-bucket",
          "my-bucket/",
          "my-bucket/footage",
          "My_Bucket",
          "ab",
          "-bucket"
        ] do
      assert bucket_error(changeset(input)) ==
               "must be the bucket name only (no s3:// or slashes): 3-63 lowercase letters, digits, dots or dashes",
             input
    end
  end
end
