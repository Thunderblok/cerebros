defmodule ThunderlineWeb.UploadController do
  @moduledoc """
  Handles file uploads for dataset creation.

  This controller receives CSV files, stores them in a temporary directory,
  and writes metadata entries to the Ash `DatasetUpload` resource.
  """

  use ThunderlineWeb, :controller
  alias Thunderline.Datasets.Upload

  def create(conn, %{
        "file" => %Plug.Upload{filename: filename, content_type: type, path: tmp_path}
      }) do
    upload_dir = Path.join(["priv", "uploads"])
    File.mkdir_p!(upload_dir)
    destination = Path.join(upload_dir, filename)
    File.cp!(tmp_path, destination)

    {:ok, _dataset} =
      Ash.create(Upload, %{
        filename: filename,
        content_type: type,
        size_bytes: File.stat!(destination).size,
        path: destination
      })

    json(conn, %{status: "ok", message: "File uploaded successfully", filename: filename})
  rescue
    e ->
      conn
      |> put_status(:internal_server_error)
      |> json(%{status: "error", message: Exception.message(e)})
  end

  def preview(conn, %{"filename" => filename}) do
    file_path = Path.join(["priv", "uploads", filename])

    case Upload.load_csv_preview(file_path, 5) do
      df when is_struct(df, Explorer.DataFrame) ->
        # Convert DataFrame to list of maps for JSON serialization
        preview_data = Explorer.DataFrame.to_rows(df)
        json(conn, %{status: "ok", preview: preview_data})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{status: "error", message: inspect(reason)})
    end
  rescue
    e ->
      conn
      |> put_status(:internal_server_error)
      |> json(%{status: "error", message: Exception.message(e)})
  end
end
