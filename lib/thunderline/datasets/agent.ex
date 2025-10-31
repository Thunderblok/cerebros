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
      primary? true
      accept [:name, :user_id, :status, :current_step]
    end

    update :update do
      accept [:name, :status, :current_step, :training_progress]
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
      constraints one_of: [
        :draft,
        :step1_work_products,
        :step1_review,
        :step2_qa,
        :step2_review,
        :step3_communications,
        :step3_review,
        :step4_references,
        :step5_training,
        :stage1_training,
        :stage2_training,
        :stage3_training,
        :stage4_training,
        :stage5_personalization,
        :deploying,
        :ready,
        :failed
      ]
      default :draft
      allow_nil? false
    end

    attribute :current_step, :integer do
      default 0
      allow_nil? false
    end

    attribute :training_progress, :integer do
      default 0
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
