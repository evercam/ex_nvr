defmodule ExNVR.Devices.Cameras.HttpClient.MilesightTest do
  use ExUnit.Case, async: true

  alias ExNVR.Devices.Cameras.HttpClient.{Axis, Milesight}
  alias ExNVR.Devices.Cameras.RemoteRecording
  alias Plug.Conn

  @uuid "1ee4e962-bdb6-4339-b27e-2d43a8be1bdb"
  @opts [timezone: "Europe/Paris"]

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass, url: "http://localhost:#{bypass.port}"}
  end

  describe "list_recordings/4" do
    test "fetch all pages", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "GET", "/vb.htm", fn conn ->
        query = URI.decode_query(conn.query_string)

        assert %{
                 "page" => "sdexplorer",
                 "use_sid" => "1",
                 "maintype" => "0",
                 "subtype" => "-1",
                 "time_start" => "2024-11-13 00:00:00",
                 "time_end" => "2024-11-13 11:59:59",
                 "iDisplayLength" => "100"
               } = query

        {rows, start} =
          case query["iDisplayStart"] do
            "0" ->
              refute Map.has_key?(query, "sid")
              {100, 0}

            "100" ->
              assert %{"sid" => "0", "uuid" => @uuid} = query
              {50, 100}
          end

        Conn.resp(conn, 200, search_response(start, rows, 150))
      end)

      assert {:ok, recordings} =
               Milesight.list_recordings(
                 url,
                 ~U[2024-11-12 23:00:00Z],
                 ~U[2024-11-13 10:59:59Z],
                 @opts
               )

      assert length(recordings) == 150

      assert %RemoteRecording{
               id: "120241113000000",
               start_date: ~U[2024-11-12 23:00:00Z],
               end_date: ~U[2024-11-12 23:00:59Z],
               size: 238_344,
               type: :schedule,
               priv_data: %{sid: "0", uuid: @uuid, index: "0"}
             } = hd(recordings)
    end

    test "search the period by half day windows", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "GET", "/vb.htm", fn conn ->
        # second window overlaps the last recording of the first one
        case URI.decode_query(conn.query_string) do
          %{"time_start" => "2024-11-13 00:00:00", "time_end" => "2024-11-13 12:00:00"} ->
            Conn.resp(conn, 200, search_response(0, 10, 10))

          %{"time_start" => "2024-11-13 12:00:00", "time_end" => "2024-11-13 23:59:59"} ->
            Conn.resp(conn, 200, search_response(9, 6, 6))
        end
      end)

      assert {:ok, recordings} =
               Milesight.list_recordings(
                 url,
                 ~U[2024-11-12 23:00:00Z],
                 ~U[2024-11-13 22:59:59Z],
                 @opts
               )

      assert length(recordings) == 15
      assert recordings == Enum.uniq_by(recordings, & &1.id)
    end

    test "return empty list when no recordings", %{bypass: bypass, url: url} do
      Bypass.expect(bypass, "GET", "/vb.htm", fn conn ->
        Conn.resp(
          conn,
          200,
          ~s({"sEcho": 0, "iTotalRecords": 0, "iTotalDisplayRecords": 0, "aaData": []})
        )
      end)

      assert {:ok, []} =
               Milesight.list_recordings(
                 url,
                 ~U[2024-11-12 23:00:00Z],
                 ~U[2024-11-13 22:59:59Z],
                 @opts
               )
    end

    test "return error on http failure", %{bypass: bypass, url: url} do
      Bypass.expect_once(bypass, "GET", "/vb.htm", &Conn.resp(&1, 404, "not found"))

      assert {:error, {404, "not found"}} =
               Milesight.list_recordings(
                 url,
                 ~U[2024-11-12 23:00:00Z],
                 ~U[2024-11-13 22:59:59Z],
                 @opts
               )
    end
  end

  @tag :tmp_dir
  test "download_recording/4", %{bypass: bypass, url: url, tmp_dir: tmp_dir} do
    recording = recording()

    Bypass.expect_once(bypass, "GET", "/dataloader.cgi", fn conn ->
      assert conn.query_string =~ "starttime=2024-11-13%2009:06:32"

      assert URI.decode_query(conn.query_string) == %{
               "dw" => "sd",
               "filename" => "120241113090632",
               "starttime" => "2024-11-13 09:06:32",
               "endtime" => "2024-11-13 09:06:39",
               "index" => "1",
               "sid" => "0",
               "uuid" => @uuid
             }

      Conn.resp(conn, 200, <<0, 1, 2, 3>>)
    end)

    dest = Path.join(tmp_dir, "recording.mp4")
    assert :ok = Milesight.download_recording(url, recording, dest, @opts)
    assert File.read!(dest) == <<0, 1, 2, 3>>
  end

  @tag :tmp_dir
  test "download_recording/4 with digest auth", %{bypass: bypass, url: url, tmp_dir: tmp_dir} do
    Bypass.expect(bypass, "GET", "/dataloader.cgi", fn conn ->
      case Conn.get_req_header(conn, "authorization") do
        ["Digest " <> _rest] ->
          Conn.resp(conn, 200, <<0, 1, 2, 3>>)

        _other ->
          conn
          |> Conn.put_resp_header(
            "www-authenticate",
            ~s(Digest qop="auth", realm="IPNC", nonce="abc")
          )
          |> Conn.resp(401, "unauthorized")
      end
    end)

    dest = Path.join(tmp_dir, "recording.mp4")
    opts = @opts ++ [username: "admin", password: "pass"]

    assert :ok = Milesight.download_recording(url, recording(), dest, opts)
    assert File.read!(dest) == <<0, 1, 2, 3>>
  end

  @tag :tmp_dir
  test "download_recording/4 returns error", %{bypass: bypass, url: url, tmp_dir: tmp_dir} do
    Bypass.expect_once(bypass, "GET", "/dataloader.cgi", &Conn.resp(&1, 404, "not found"))

    dest = Path.join(tmp_dir, "recording.mp4")

    assert {:error, {404, "not found"}} =
             Milesight.download_recording(url, recording(), dest, @opts)

    refute File.exists?(dest)
  end

  test "other vendors are not implemented", %{url: url} do
    assert {:error, :not_implemented} =
             Axis.list_recordings(url, DateTime.utc_now(), DateTime.utc_now(), [])

    assert {:error, :not_implemented} =
             Axis.download_recording(url, %RemoteRecording{}, "/tmp/x.mp4", [])
  end

  defp recording do
    %RemoteRecording{
      id: "120241113090632",
      start_date: ~U[2024-11-13 08:06:32Z],
      end_date: ~U[2024-11-13 08:06:39Z],
      priv_data: %{sid: "0", uuid: @uuid, index: "1"}
    }
  end

  defp search_response(start, count, total) do
    base = ~N[2024-11-13 00:00:00]

    rows =
      Enum.map(start..(start + count - 1), fn idx ->
        start_time = NaiveDateTime.add(base, idx * 60)
        end_time = NaiveDateTime.add(start_time, 59)

        [
          "1" <> Calendar.strftime(start_time, "%Y%m%d%H%M%S"),
          NaiveDateTime.to_string(start_time),
          NaiveDateTime.to_string(end_time),
          "1",
          "238344",
          "0&#{@uuid}",
          "0"
        ]
      end)

    JSON.encode!(%{
      "sEcho" => 0,
      "iTotalRecords" => total,
      "iTotalDisplayRecords" => count,
      "aaData" => rows
    })
  end
end
