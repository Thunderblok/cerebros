defmodule Thunderline.Datasets do
  @moduledoc """
  Domain for managing dataset uploads and processing.
  """

  use Ash.Domain,
    otp_app: :thunderline,
    extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Thunderline.Datasets.Upload
  end
end
