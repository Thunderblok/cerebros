defmodule ThunderlineWeb.UploadControllerTest do
  use ThunderlineWeb.ConnCase, async: true

  alias Thunderline.Datasets.Upload

  @upload_path Path.expand("tmp/test_uploads")

  setup do
    File.mkdir_p!(@upload_path)
    :ok
  end

  test "POST /api/uploads uploads CSV and creates Upload record", %{conn: conn} do
    file = Path.join(@upload_path, "sample.csv")
    File.write!(file, "header1,header2\nvalueA,valueB\n")

    upload = %Plug.Upload{
      filename: "sample.csv",
      path: file,
      content_type: "text/csv"
    }

    conn =
      post(conn, "/api/uploads", %{"file" => upload})

    assert %{"status" => "ok"} = json_response(conn, 200)

    assert [%Upload{filename: "sample.csv"}] = Upload.list_uploads()
  end

  test "GET /api/uploads/preview/:filename returns CSV preview", %{conn: conn} do
    file = Path.join(["priv", "uploads", "previewer.csv"])
    File.mkdir_p!("priv/uploads")
    File.write!(file, "col1,col2\n1,2\n3,4\n")

    Upload.create_upload(%{
      filename: "previewer.csv",
      path: file,
      content_type: "text/csv",
      size_bytes: File.stat!(file).size
    })

    conn = get(conn, "/api/uploads/preview/previewer.csv")

    res = json_response(conn, 200)
    assert res["status"] == "ok"
    assert is_list(res["preview"])
  end
end
