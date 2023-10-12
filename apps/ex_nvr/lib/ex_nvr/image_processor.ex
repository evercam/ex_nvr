defmodule ExNVR.ImageProcessor do
  use Export.Python


  def undistort_snapshot(image) do
    run(
      "image_processing",
      "undistort_image",
      [image]
    )
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
