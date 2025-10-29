# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Thunderline.Repo.insert!(%Thunderline.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Thunderline.Accounts.User

# Add mo@okoracle.com to the database
# Since we don't have a basic create action, we'll insert directly into the repo
case Thunderline.Repo.insert(%User{email: "mo@okoracle.com"}) do
  {:ok, user} ->
    IO.puts("✅ User created successfully!")
    IO.puts("   Email: #{user.email}")
    IO.puts("   ID: #{user.id}")

  {:error, changeset} ->
    IO.puts("❌ Error creating user: #{inspect(changeset)}")
end
