defmodule ExNVR.ImageProcessor do
  use Export.Python
  alias Evision, as: Cv
  require Nx

  require Logger

  @pfov 100
  @fov 140

  def undistort_snapshot(image_binary) do
    distorted_img = Cv.imdecode(image_binary, Cv.Constant.cv_IMREAD_ANYCOLOR())

    {height, width, _} = distorted_img.shape
    x_center = Integer.floor_div(width, 2)
    y_center = Integer.floor_div(height, 2)

    dimension = :math.sqrt(:math.pow(width, 2) + :math.pow(height, 2))
    ofoc_inv = (2 * :math.tan(@pfov * :math.pi() / 360)) / dimension

    i = Nx.iota({height, width}, axis: 1)
    |> Nx.add(-x_center)
    j = Nx.iota({height, width}, axis: 0)
    |> Nx.add(-y_center)

    hypot = Nx.add(Nx.pow(i, 2), Nx.pow(j, 2))
    |> Nx.sqrt()

    IO.puts "0"

    rr = hypot
    |> Nx.multiply(ofoc_inv)
    |> Nx.atan()
    |> typed_undistort(@fov, dimension, "orthographic")

    IO.puts "1"

    xs = rr
    |> Nx.divide(hypot)
    |> Nx.multiply(i)
    |> Nx.add(x_center)
    |> Nx.clip(0, width - 1)
    |> Nx.as_type(:s32)

    IO.puts "2.5"

    ys = rr
    |> Nx.divide(hypot)
    |> Nx.multiply(j)
    |> Nx.multiply(0.9)
    |> Nx.add(y_center)
    |> Nx.clip(0, height - 1)
    |> Nx.as_type(:s32)

    IO.inspect Nx.reduce_max(ys)
    IO.inspect Nx.reduce_min(ys)

    target_indices = Enum.zip(Nx.to_flat_list(ys), Nx.to_flat_list(xs))
    |> Enum.flat_map(fn {a, b} -> Enum.map(0..2, fn enum -> [a, b, enum] end) end)
    |> Nx.tensor()

    input_indices = Enum.zip(Nx.to_flat_list(Nx.add(j, y_center)), Nx.to_flat_list(Nx.add(i, x_center)))
    |> Enum.flat_map(fn {a, b} -> Enum.map(0..2, fn enum -> [a, b, enum] end) end)
    |> Nx.tensor()

    IO.puts "3"

    Cv.Mat.to_nx(distorted_img, Torchx.Backend)
    |> then(&Nx.indexed_put(&1, input_indices, Nx.gather(&1, target_indices)))
    |> Nx.as_type(:u8)
    |> Cv.Mat.from_nx_2d()
    |> then(&Cv.imencode(".png", &1))
    |> Base.encode64()

    # run(
    #   "image_processing",
    #   "undistort_image",
    #   [image_binary]
    # )
  end

  defp typed_undistort(phiang, fov, dimension, "orthographic") do
    phiang
    |> Nx.sin()
    |> Nx.multiply(dimension / (2.0 * :math.sin(fov * :math.pi() / 360)))
  end

  defp run(module, function, args) do
    {:ok, pid} = Python.start(python_path: python_modules_path())

    try do
      Python.call(pid, module, function, args)
    after
      Python.stop(pid)
    end
  end

  def python_modules_path() do
    Path.join([Application.app_dir(:ex_nvr), "priv", "python"])
  end
end
