# How to Monitor Training Jobs

## The Problem We Just Fixed

Your training jobs were **failing** with this error:
```
Expected an `Ash.Resource` in `Ash.get/3`, got: Thunderline.Training.Agent
```

The worker was using the wrong module name: `Thunderline.Training.Agent` instead of `Thunderline.Agents.Agent`.

**✅ This has been fixed!** The server has been restarted with the corrected code.

---

## How to Check Job Status

### Quick Check (Run Anytime)
```bash
mix run check_jobs.exs
```

This shows:
- Total jobs and their states (completed, executing, discarded, etc.)
- Last 10 jobs with full details
- Currently executing or queued jobs

### What Job States Mean
- `available` - Ready to run, waiting in queue
- `executing` - Currently running
- `completed` - Finished successfully ✅
- `discarded` - Failed after max retries (3 attempts) ❌
- `retryable` - Failed but will retry
- `scheduled` - Scheduled for future execution

---

## Watch Jobs in Real-Time

### Option 1: Server Logs
When the server is running (`mix phx.server`), watch for these log messages:

```
[info] Starting Cerebros training for agent <id>
[info] Processed X chunks for agent <id>
[info] Saved training CSV to .../training_data_<timestamp>.csv
[info] Sending X chunks to Cerebros...
```

### Option 2: Oban Web Dashboard (if installed)
Visit: `http://localhost:4001/oban` (needs oban_web setup)

### Option 3: IEx Console
```bash
iex -S mix phx.server
```

Then run:
```elixir
# Check all jobs
Thunderline.Repo.all(Oban.Job)

# Check only executing jobs
import Ecto.Query
from(j in Oban.Job, where: j.state == "executing") |> Thunderline.Repo.all()

# Check jobs for specific agent
from(j in Oban.Job, where: fragment("? ->> 'agent_id' = ?", j.args, ^"your-agent-id")) |> Thunderline.Repo.all()
```

---

## Test Training Pipeline Again

Now that the bug is fixed:

1. **Create a new agent**
   - Visit: http://localhost:4001/agents/new
   
2. **Upload documents** in Steps 1, 3, and 4
   - Use `test_sample_document.txt` (in project root) or your own files
   
3. **Click through to Step 5** (Training)
   - The system will automatically queue a training job
   
4. **Monitor the job**
   ```bash
   # In another terminal
   watch -n 2 'mix run check_jobs.exs'
   ```
   
5. **Check server logs** for progress:
   ```
   [info] Starting Cerebros training for agent ...
   [info] Processed 15 chunks for agent ...
   [info] Saved training CSV to ...
   ```

---

## What Happens During Training

1. **Job Queued**: Oban creates a job in the `cerebros_training` queue
2. **Job Executes**: Worker fetches agent and documents
3. **Process Documents**: Chunks documents into training data
4. **Save CSV**: Creates `training_data_<timestamp>.csv` in `priv/nfs/agents/{id}/processed/`
5. **Call Cerebros**: Sends data to Python training script
6. **Update Status**: Marks training as complete

---

## Troubleshooting

### Job shows as "discarded"
- Check errors in `check_jobs.exs` output
- Look at server logs for stack traces
- Jobs are discarded after 3 failed attempts

### No jobs appearing
- Make sure Oban is configured with `cerebros_training` queue
- Check `config/config.exs` has: `queues: [default: 10, cerebros_training: 5]`

### Training seems stuck
- Run `mix run check_jobs.exs` to see if job is executing
- Check for errors in server logs
- Verify Python wrapper is executable: `chmod +x cerebros-core-algorithm-alpha/train_model_wrapper.py`

---

## Quick Commands Reference

```bash
# Check job status
mix run check_jobs.exs

# Watch jobs continuously (updates every 2 seconds)
watch -n 2 'mix run check_jobs.exs'

# Restart server
pkill -9 beam.smp; sleep 2; mix phx.server

# Check if server is running
ps aux | grep beam.smp | grep phx.server

# View processed files
ls -la priv/nfs/agents/*/processed/

# View uploaded documents
ls -la priv/nfs/agents/*/work_products/
ls -la priv/nfs/agents/*/communications/
ls -la priv/nfs/agents/*/reference/
```
