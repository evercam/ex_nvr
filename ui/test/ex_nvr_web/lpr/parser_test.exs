defmodule ExNVRWeb.LPR.ParserTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVRWeb.LPR.Parser

  describe "milesight parser" do
    test "parse lpr data" do
      data = %{
        "device" => "Network Camera",
        "time" => "2024-02-01 06:00:05.509",
        "time_msec" => "2024-02-01 06:00:05.509",
        "plate" => "62D3680",
        "type" => "Visitor",
        "speed" => "-",
        "direction" => "-",
        "detection_region" => "1",
        "region" => "LVA",
        "resolution_width" => "1920",
        "resolution_height" => "1080",
        "coordinate_x1" => "1014",
        "coordinate_y1" => "624",
        "coordinate_x2" => "1110",
        "coordinate_y2" => "666",
        "confidence" => "-",
        "plate_color" => "White",
        "vehicle_type" => "-",
        "vehicle_color" => "-",
        "Vehicle Brand" => "-",
        "plate_image" =>
          "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCAAqAGADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD5iooFA6UAIBS49BQiu7BUUsx7AZqf7Ffk4+x3Gf8ArmaAK+KBV1NJ1R84spffIxUv9hX68yiOMf7TUAZtIK110Gfbk3EeP9nJo/seIffvBkdRtoAyKMitiGx0sEmS4dgvUCpduhIm6K2mmOf4mxQBhZFLkYxW691Zoo+z6bH757VDr/lG2iaOIJuPYUAZH40+3ALgGmVPYR+ZcBd233NAG54WjU30rKikpGzDPerP9ranKFFnlCc5CnqAaZoUZt7udmbdiJ8EepU1mlQPJLSsjCLjHc5oA1dRutYi2N5zooxuUv1yak1iRprMnzAHDKOuaqTXazXcFvKshVVXdxnJqzrNoEgVra23yOQ5CdhQBVtnEUbRSyOdr4GBmoLqBYrlNu5mfpmrMEZRS1w0cO5s4Lciq8jRmYvPfw7V+5t60ARCQ+S6G3VHzw3rUWJC+AERuvWgy2Kowa7klJ9FqNrqwCBRFK5HcmgBT2PmbTjkevNP8RMP3MYP3VzULajHu3JZx5xgFjmql1O9xKZHxmgCOnI2MkHFMpR0oAt2mo3Ftu2EHPrTzqlyQBiIbeh2DiqNIO9AFl767ckmZgT6cVE89w/355G+rGmCjtQAcnqSaTFIOtKaADiikpR3oAM0lFFAH//Z"
      }

      plate_image =
        <<255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 255, 219, 0,
          67, 0, 5, 3, 4, 4, 4, 3, 5, 4, 4, 4, 5, 5, 5, 6, 7, 12, 8, 7, 7, 7, 7, 15, 11, 11, 9,
          12, 17, 15, 18, 18, 17, 15, 17, 17, 19, 22, 28, 23, 19, 20, 26, 21, 17, 17, 24, 33, 24,
          26, 29, 29, 31, 31, 31, 19, 23, 34, 36, 34, 30, 36, 28, 30, 31, 30, 255, 219, 0, 67, 1,
          5, 5, 5, 7, 6, 7, 14, 8, 8, 14, 30, 20, 17, 20, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
          30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
          30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 255, 192, 0, 17,
          8, 0, 42, 0, 96, 3, 1, 34, 0, 2, 17, 1, 3, 17, 1, 255, 196, 0, 31, 0, 0, 1, 5, 1, 1, 1,
          1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 255, 196, 0, 181,
          16, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125, 1, 2, 3, 0, 4, 17, 5, 18, 33, 49,
          65, 6, 19, 81, 97, 7, 34, 113, 20, 50, 129, 145, 161, 8, 35, 66, 177, 193, 21, 82, 209,
          240, 36, 51, 98, 114, 130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40, 41, 42, 52, 53,
          54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99,
          100, 101, 102, 103, 104, 105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 131, 132,
          133, 134, 135, 136, 137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163,
          164, 165, 166, 167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194,
          195, 196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218,
          225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 241, 242, 243, 244, 245, 246, 247,
          248, 249, 250, 255, 196, 0, 31, 1, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1,
          2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 255, 196, 0, 181, 17, 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4,
          4, 0, 1, 2, 119, 0, 1, 2, 3, 17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113, 19, 34, 50,
          129, 8, 20, 66, 145, 161, 177, 193, 9, 35, 51, 82, 240, 21, 98, 114, 209, 10, 22, 36,
          52, 225, 37, 241, 23, 24, 25, 26, 38, 39, 40, 41, 42, 53, 54, 55, 56, 57, 58, 67, 68,
          69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104,
          105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135, 136,
          137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167,
          168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198,
          199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 226, 227, 228, 229,
          230, 231, 232, 233, 234, 242, 243, 244, 245, 246, 247, 248, 249, 250, 255, 218, 0, 12,
          3, 1, 0, 2, 17, 3, 17, 0, 63, 0, 249, 138, 138, 5, 3, 165, 0, 32, 20, 184, 244, 20, 34,
          187, 176, 84, 82, 204, 123, 1, 154, 159, 236, 87, 228, 227, 236, 119, 25, 255, 0, 174,
          102, 128, 43, 226, 129, 87, 83, 73, 213, 31, 56, 178, 151, 223, 35, 21, 47, 246, 21,
          250, 243, 40, 142, 49, 254, 211, 80, 6, 109, 32, 173, 117, 208, 103, 219, 147, 113, 30,
          63, 217, 201, 163, 251, 30, 33, 247, 239, 6, 71, 81, 182, 128, 50, 40, 200, 173, 136,
          108, 116, 176, 73, 146, 225, 216, 47, 80, 42, 93, 186, 18, 38, 232, 173, 166, 152, 231,
          248, 155, 20, 1, 133, 145, 75, 145, 140, 86, 235, 221, 89, 162, 143, 179, 233, 177, 251,
          231, 181, 67, 175, 249, 70, 218, 38, 142, 32, 155, 143, 97, 64, 25, 31, 141, 62, 220, 2,
          224, 26, 101, 79, 97, 31, 153, 112, 23, 118, 223, 115, 64, 27, 158, 22, 141, 77, 244,
          172, 168, 164, 164, 108, 195, 61, 234, 207, 246, 182, 167, 40, 81, 103, 148, 39, 57, 10,
          122, 128, 105, 154, 20, 102, 222, 238, 118, 102, 221, 136, 159, 4, 122, 149, 53, 154,
          84, 15, 36, 180, 172, 140, 34, 227, 29, 206, 104, 3, 87, 81, 186, 214, 34, 216, 222,
          115, 162, 140, 110, 82, 253, 114, 106, 77, 98, 70, 154, 204, 159, 48, 7, 12, 163, 174,
          106, 164, 215, 107, 53, 220, 22, 242, 172, 133, 85, 87, 119, 25, 201, 171, 58, 205, 160,
          72, 21, 173, 173, 183, 200, 228, 57, 9, 216, 80, 5, 91, 103, 17, 70, 209, 75, 35, 157,
          175, 129, 129, 154, 130, 234, 5, 138, 229, 54, 238, 102, 126, 153, 171, 48, 70, 81, 75,
          92, 52, 112, 238, 108, 224, 183, 34, 171, 200, 209, 153, 139, 207, 127, 14, 213, 251,
          155, 122, 208, 4, 66, 67, 228, 186, 27, 117, 71, 207, 13, 235, 81, 98, 66, 248, 1, 17,
          186, 245, 160, 203, 98, 168, 193, 174, 228, 148, 159, 69, 168, 218, 234, 192, 32, 81,
          20, 174, 71, 114, 104, 1, 79, 99, 230, 109, 56, 228, 122, 243, 79, 241, 19, 15, 220,
          198, 15, 221, 92, 212, 45, 168, 199, 187, 114, 89, 199, 156, 96, 22, 57, 170, 151, 83,
          189, 196, 166, 71, 198, 104, 2, 58, 114, 54, 50, 65, 197, 50, 148, 116, 160, 11, 118,
          154, 141, 197, 182, 237, 132, 28, 250, 211, 206, 169, 114, 64, 24, 136, 109, 232, 118,
          14, 42, 141, 32, 239, 64, 22, 94, 250, 237, 201, 38, 102, 4, 250, 113, 81, 60, 247, 15,
          247, 231, 145, 190, 172, 105, 130, 142, 212, 0, 114, 122, 146, 105, 49, 72, 58, 210,
          154, 0, 56, 162, 146, 148, 119, 160, 3, 52, 148, 81, 64, 31, 255, 217>>

      assert {event, ^plate_image} = Parser.Milesight.parse(data, "Africa/Algiers")

      assert Date.compare(event.capture_time, ~U(2024-02-01 05:00:05.509Z)) == :eq

      assert %{
               plate_number: "62D3680",
               direction: :unknown,
               list_type: :other,
               metadata: %{
                 bounding_box: [0.53, 0.58, 0.58, 0.62],
                 vehicle_color: "-",
                 vehicle_type: "-"
               }
             } = event
    end

    test "raise on parse error" do
      data = %{
        "device" => "Network Camera",
        "time" => "2024-02-01 06:0005.509",
        "plate" => "62D3680"
      }

      assert_raise ArgumentError, fn -> Parser.Milesight.parse(data, "Africa/Algiers") end
    end
  end
end
