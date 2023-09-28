defmodule ExNVR.Pipeline.Source.RTSP.IsapiMetadata do
  @moduledoc """
  An RTP depayloader for Hikvision ISAPI metadata. Only ANPR events are captured.
  """

  use Membrane.Filter

  import SweetXml, only: [sigil_x: 2, transform_by: 2]

  alias Membrane.{Buffer, RTP}

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: RTP

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{acc: <<>>}}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) when not buffer.metadata.rtp.marker do
    {[], %{state | acc: state.acc <> buffer.payload}}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload, metadata: metadata}, _ctx, state) do
    acc = state.acc <> payload

    if metadata = parse(acc) do
      {[buffer: {:output, %Buffer{payload: <<>>, metadata: metadata}}], %{state | acc: <<>>}}
    else
      {[], %{state | acc: <<>>}}
    end
  end

  defp parse(xml_data) do
    data =
      xml_data
      |> SweetXml.xpath(~x"//Metadata",
        type: ~x"./type/text()"s,
        sub_type: ~x"./subType/text()"s,
        time: ~x"./time/text()"s |> transform_by(&to_datetime/1),
        device: [
          ~x"./DevInfo",
          ip_address: ~x"./ipAddress/text()"s,
          port: ~x"./portNo/text()"i,
          mac_address: ~x"./macAddress/text()"s,
          channel: ~x"./channel/text()"i
        ]
      )

    case {data[:type], data[:sub_type]} do
      {"activityTarget", "ANPR"} ->
        Map.merge(data, parse_sub_type(:anpr, xml_data))

      {_type, _sub_type} ->
        nil
    end
  end

  defp parse_sub_type(:anpr, xml) do
    anpr =
      SweetXml.xpath(xml, ~x"//Metadata//TargetDetection/TargetList",
        targets: [
          ~x"./Target"l,
          target_id: ~x"./targetID/text()"i,
          recognition: ~x"./recognition/text()"so,
          rule_id: ~x"./ruleID/text()"io,
          region: [
            ~x"./RegionList/Region/Point"lo,
            x: ~x"./x/text()"i,
            y: ~x"./y/text()"i
          ],
          properties: [
            ~x"./PropertyList/Property"l,
            name: ~x"./description/text()"s,
            value: ~x"./value/text()"s
          ]
        ]
      )

    update_in(anpr, [:targets], fn targets ->
      Enum.map(targets, fn target ->
        update_in(target, [:region], fn region ->
          IO.inspect(region)
          %{x: x1, y: y1} = Enum.at(region, 0)
          %{x: x2, y: y2} = Enum.at(region, 2)

          [x1, y1, x2, y2]
        end)
        |> update_in([:properties], fn properties ->
          properties
          |> Enum.map(&{&1.name, &1.value})
          |> Enum.into(%{})
        end)
      end)
    end)
  end

  defp to_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> value
    end
  end
end
