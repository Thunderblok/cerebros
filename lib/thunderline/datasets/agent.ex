defmodule Thunderline.Datasets.Agent do
  use Ash.Resource,
    domain: Thunderline.Datasets,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "agents"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :user_id, :status]
    end

    update :update do
      accept [:name, :status]
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:draft, :collecting_prompts, :collecting_references, :collecting_communications, :collecting_procedures, :processing, :ready]
      default :draft
      allow_nil? false
    end

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Thunderline.Accounts.User do
      allow_nil? false
    end

    has_many :documents, Thunderline.Datasets.AgentDocument
  end

  admin do
    table_columns [:id, :name, :user_id, :status, :created_at]
  end
end
