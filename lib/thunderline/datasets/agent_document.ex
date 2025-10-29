defmodule Thunderline.Datasets.AgentDocument do
  use Ash.Resource,
    domain: Thunderline.Datasets,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAdmin.Resource]

  postgres do
    table "agent_documents"
    repo Thunderline.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:agent_id, :document_type, :file_path, :original_filename, :status, :is_synthetic, :source_document_id, :synthetic_prompt, :synthetic_reasoning, :synthetic_response]
    end

    update :update do
      accept [:status, :file_path, :synthetic_prompt, :synthetic_reasoning, :synthetic_response]
    end

    read :for_agent do
      argument :agent_id, :uuid, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id))
    end

    read :by_type do
      argument :agent_id, :uuid, allow_nil?: false
      argument :document_type, :atom, allow_nil?: false
      filter expr(agent_id == ^arg(:agent_id) and document_type == ^arg(:document_type))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :agent_id, :uuid do
      allow_nil? false
    end

    attribute :document_type, :atom do
      constraints one_of: [:work_product, :qa_pair, :communication, :reference]
      allow_nil? false
    end

    attribute :file_path, :string do
      allow_nil? false
    end

    attribute :original_filename, :string do
      allow_nil? false
    end

    attribute :status, :atom do
      constraints one_of: [:uploaded, :processing, :completed, :failed, :approved, :rejected]
      default :uploaded
      allow_nil? false
    end

    attribute :is_synthetic, :boolean do
      default false
      allow_nil? false
    end

    attribute :source_document_id, :uuid do
      allow_nil? true
    end

    attribute :synthetic_prompt, :string
    attribute :synthetic_reasoning, :string
    attribute :synthetic_response, :string

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :agent, Thunderline.Datasets.Agent do
      allow_nil? false
    end
  end

  admin do
    table_columns [:id, :agent_id, :document_type, :original_filename, :status, :created_at]
  end
end
