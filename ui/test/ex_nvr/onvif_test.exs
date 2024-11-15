defmodule ExNVR.OnvifTest do
  @moduledoc false

  use ExUnit.Case

  import Mockery

  alias ExNVR.Onvif

  @response """
  <?xml version="1.0" encoding="UTF-8"?>
  <Envelope xmlns="http://www.w3.org/2003/05/soap-envelope">
  <Header>
  <wsa:MessageID xmlns:wsa="http://www.w3.org/2005/08/addressing">uuid:de305d54-75b4-431b-adb2-eb6b9e546014</wsa:MessageID>
  <wsa:RelatesTo xmlns:wsa="http://www.w3.org/2005/08/addressing">uuid:7f6a9c73-d26f-4dba-9ccf-258aca778a9b</wsa:RelatesTo>
  <wsa:To xmlns:wsa="http://www.w3.org/2005/08/addressing">http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous</wsa:To>
  </Header>
  <Body>
  <d:ProbeMatches>
  <d:ProbeMatch>
  <d:EndpointReference>
  <Address>urn:uuid:7586E1A5-BD6D-49AC-8C08-9D48115B57C6</Address>
  <ReferenceParameters>
  <ns3:Types xmlns:ns3="http://schemas.xmlsoap.org/ws/2005/04/discovery">dn:NetworkVideoTransmitter</ns3:Types>
  </ReferenceParameters>
  </d:EndpointReference>
  <d:Types>dn:NetworkVideoTransmitter</d:Types>
  <d:Scopes>onvif://www.onvif.org/type/video_encoder onvif://www.onvif.org/type/audio_encoder onvif://www.onvif.org/hardware/JukeBox onvif://www.onvif.org/name/Evercam%20Ltd</d:Scopes>
  <d:XAddrs>http://192.168.1.10/onvif/device_service http://192.168.1.10/onvif/device_service</d:XAddrs>
  <d:MetadataVersion>1</d:MetadataVersion>
  </d:ProbeMatch>
  </d:ProbeMatches>
  </Body>
  </Envelope>
  """

  @default_media_uri "http://192.168.1.100/onvif/Media"

  describe "Probe network" do
    test "for onvif devices" do
      mock_gen_udp()

      mock(:gen_udp, [recv: 3], fn socket, 0, _timeout ->
        case Agent.get_and_update(socket, &{&1, &1 + 1}) do
          0 -> {:ok, {{192, 168, 1, 100}, 9630, @response}}
          _ -> {:error, :timeout}
        end
      end)

      mock(Soap, :call, {:ok, %{status_code: 200}})

      assert {:ok,
              [
                %{
                  types: ["dn:NetworkVideoTransmitter"],
                  url: "http://192.168.1.10/onvif/device_service",
                  hardware: "JukeBox",
                  name: "Evercam Ltd"
                }
              ]} = Onvif.discover()
    end

    test "with not reachable addresses in answer" do
      mock_gen_udp()

      mock(:gen_udp, [recv: 3], fn socket, 0, _timeout ->
        case Agent.get_and_update(socket, &{&1, &1 + 1}) do
          0 -> {:ok, {{192, 168, 1, 100}, 9630, @response}}
          _ -> {:error, :timeout}
        end
      end)

      mock(Soap, :call, {:error, :timeout})

      assert {:ok, []} = Onvif.discover()
    end

    test "timeout" do
      mock_gen_udp()
      mock(:gen_udp, :recv, {:error, :timeout})

      assert {:ok, []} = Onvif.discover()
    end

    test "failed" do
      mock(:gen_udp, :open, {:error, :eagain})
      assert {:error, :eagain} = Onvif.discover()
    end
  end

  describe "Operations" do
    test "call an operation" do
      ref_file = "../fixtures/onvif/GetProfilesResponse.xml" |> Path.expand(__DIR__)
      body = %{"Type" => "All"}

      mock_operation("GetProfiles", body, ref_file)

      assert {:ok, %{get_profiles_response: profiles}} =
               Onvif.call(@default_media_uri, :get_profiles, %{"Type" => "All"})

      assert %{get_profiles_response: _profiles} =
               Onvif.call!(@default_media_uri, :get_profiles, %{"Type" => "All"})

      assert length(profiles) == 2

      assert Enum.map(profiles, fn {_, profile} -> profile.token end) == [
               "Profile_1",
               "Profile_2"
             ]
    end

    test "call failed" do
      ref_file = "../fixtures/onvif/GetProfilesResponse.xml" |> Path.expand(__DIR__)
      mock_operation("GetProfiles", :error, ref_file)

      assert {:error, :invalid_operation} = Onvif.call(@default_media_uri, :get_profiles, :error)
      assert_raise RuntimeError, fn -> Onvif.call!(@default_media_uri, :get_profiles, :error) end
    end
  end

  defp mock_gen_udp() do
    mock(:gen_udp, :open, Agent.start(fn -> 0 end))

    mock(:gen_udp, [send: 4], fn _socket, {239, 255, 255, 250}, 3702, request ->
      assert request =~ "tds:Device"
      :ok
    end)
  end

  defp mock_operation(operation, body, reference_file) do
    mock(
      Soap,
      [call: 3],
      fn _wsdl, ^operation, ^body ->
        case body do
          :error ->
            {:error, :invalid_operation}

          _ ->
            {:ok, %Soap.Response{status_code: 200, body: File.read!(reference_file)}}
        end
      end
    )
  end
end
