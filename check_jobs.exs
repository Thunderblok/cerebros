# Check Oban jobs
alias Thunderline.Repo

jobs = Repo.all(Oban.Job)

IO.puts("\n=== OBAN JOBS SUMMARY ===")
IO.puts("Total jobs: #{length(jobs)}")

# Group by state
by_state = Enum.group_by(jobs, & &1.state)
Enum.each(by_state, fn {state, jobs} ->
  IO.puts("  #{state}: #{length(jobs)}")
end)

IO.puts("\n=== RECENT JOBS (Last 10) ===")
import Ecto.Query
recent = from(j in Oban.Job,
  order_by: [desc: j.inserted_at],
  limit: 10
) |> Repo.all()

Enum.each(recent, fn job ->
  agent_id = job.args["agent_id"]
  IO.puts("\n Job ##{job.id}")
  IO.puts("   Worker: #{job.worker}")
  IO.puts("   Queue: #{job.queue}")
  IO.puts("   State: #{job.state}")
  IO.puts("   Agent ID: #{agent_id}")
  IO.puts("   Attempt: #{job.attempt}/#{job.max_attempts}")
  IO.puts("   Inserted: #{job.inserted_at}")
  IO.puts("   Attempted: #{job.attempted_at}")
  IO.puts("   Completed: #{job.completed_at}")

  if job.errors != [] do
    IO.puts("   Errors: #{inspect(job.errors, pretty: true)}")
  end
end)

IO.puts("\n=== EXECUTING/AVAILABLE JOBS ===")
active = from(j in Oban.Job,
  where: j.state in ["executing", "available"]
) |> Repo.all()

if active == [] do
  IO.puts("No jobs currently executing or queued")
else
  Enum.each(active, fn job ->
    IO.puts("  #{job.state} - #{job.worker} (Job ##{job.id})")
  end)
end
