defmodule Thunderline.Datasets.Upload do
  @moduledoc """
  Ash resource responsible for managing dataset upload records and handling CSV ingestion.

  This resource stores metadata about each upload and uses Explorer for data preview
  and Nx for preprocessing preview tasks.
  """

  use Ash.Resource,
    domain: Thunderline.Datasets,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "dataset_uploads"
    repo Thunderline.Repo
  end

  code_interface do
    define :create_upload, action: :create
    define :list_uploads, action: :read
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:filename, :content_type, :size_bytes, :path]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :filename, :string, allow_nil?: false
    attribute :content_type, :string
    attribute :size_bytes, :integer
    attribute :path, :string, allow_nil?: false
    attribute :metadata, :map, default: %{}
    timestamps()
  end

  def load_csv_preview(file_path, limit \\ 5) do
    require Explorer.DataFrame

    case Explorer.DataFrame.from_csv(file_path, dtypes: :auto) do
      {:ok, df} -> Explorer.DataFrame.head(df, limit)
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  @spec list_uploads() :: [t()]
  def list_uploads do
    Ash.read!(__MODULE__)
  end

  @spec create_upload(map()) :: {:ok, t()} | {:error, term()}
  def create_upload(attrs) when is_map(attrs) do
    Ash.create(__MODULE__, attrs)
  end
end
