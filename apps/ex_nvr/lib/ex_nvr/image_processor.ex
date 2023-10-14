defmodule ExNVR.ImageProcessor do
  use Export.Python
  alias Evision, as: Cv
  require Nx
  import Nx.Defn

  require Logger

  @pfov 100
  @fov 180

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

    hypot = Nx.sum(Nx.pow(i, 2), Nx.pow(j, 2))
    |> Nx.sqrt()

    rr = hypot
    |> Nx.multiply(ofoc_inv)
    |> Nx.atan()
    |> typed_undistort(@fov, dimension, "orthographic")


    Cv.Mat.to_nx(distorted_img)

    # with image <- Cv.imdecode(binary, Cv.Constant.cv_IMREAD_ANYCOLOR()),
    #      decoded_img <- Cv.imencode(".png", image) do
    #   Base.encode64(decoded_img)
    # else
    #   error ->
    #     error
    # end
    # run(
    #   "image_processing",
    #   "undistort_image",
    #   [image]
    # )
  end

  defp typed_undistort(phiang, fov, dimension, "orthographic") do
    phiang
    |> Nx.sin()
    |> Nx.multiply(dimension / (2.0 * :math.sin(fov * :math.pi() / 720)))
  end

  defpn safe_divide(a, b) do
    while {tensor, acc = 0}, i <- 0..Nx.axis_size(tensor, 0)-1 do
      acc + tensor[i]
    end
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
