defmodule Thunderline.Repo do
  use Ecto.Repo,
    otp_app: :thunderline,
    adapter: Ecto.Adapters.Postgres
end
