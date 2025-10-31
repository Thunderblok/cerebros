# Real-Time Training Monitoring 🔍

## Quick Start

### Watch Training Logs in Real-Time
```bash
./watch_training.sh
```

This will show you:
- 🚀 When training jobs start
- ✓ Each step completing successfully (agent fetch, document processing, CSV creation, Cerebros call)
- ✗ Any errors that occur
- ✅ When training completes

Press `Ctrl+C` to stop watching.

---

## Terminal Output Explained

When you go through the wizard and click "Complete Setup," you should see:

```
🚀 Starting Cerebros training for agent <id>
✓ Agent fetched: {:ok, %Thunderline.Datasets.Agent{...}}
✓ Processed 15 chunks
✓ CSV saved to priv/nfs/agents/<id>/processed/training_data_<timestamp>.csv
✓ Cerebros training initiated successfully
✅ Training pipeline complete for agent <id>
```

If you see this, **training is working!** 🎉

---

## What Each Step Does

### 1. 🚀 Starting Cerebros training
The Oban job is executing

### 2. ✓ Agent fetched
Worker successfully loaded agent from database

### 3. ✓ Processed X chunks
Documents were split into training chunks
- If you see "Processed 0 chunks" → You didn't upload any files

### 4. ✓ CSV saved
Training data written to CSV file for Cerebros

### 5. ✓ Cerebros training initiated
Python script called successfully to train the model

### 6. ✅ Training pipeline complete
Everything succeeded!

---

## Troubleshooting

### No output after "Starting Cerebros training"
The job might be stuck or erroring. Check:
```bash
mix run check_jobs.exs
```

Look for "discarded" jobs with errors.

### "Processed 0 chunks"
You didn't upload any documents! Go back and upload files in:
- Step 1: Work Products
- Step 3: Communications
- Step 4: Reference Materials

### "✗ Agent fetched failed"
Database issue. The agent ID might be invalid.

### "✗ CSV save failed"
Permission issue. Check:
```bash
ls -la priv/nfs/agents/
```

### "✗ Cerebros call failed"
The Python script failed. Check:
1. Is Python installed? `python3 --version`
2. Is the script executable? `chmod +x cerebros-core-algorithm-alpha/train_model_wrapper.py`
3. Does the script exist? `ls -la cerebros-core-algorithm-alpha/`

---

## Other Monitoring Tools

### Check Job Status
```bash
mix run check_jobs.exs
```

Shows all jobs (completed, executing, discarded, etc.)

### Watch Jobs Continuously
```bash
watch -n 2 'mix run check_jobs.exs'
```

Updates every 2 seconds.

### Check Server Logs
```bash
tail -f /tmp/thunderline_server.log
```

Raw server output (very verbose).

### Check for Errors Only
```bash
tail -f /tmp/thunderline_server.log | grep -i "error\|failed"
```

---

## The Fix Applied

### What Was Wrong
The worker was using the wrong module path:
- ❌ `Thunderline.Agents.Agent` (doesn't exist)
- ✅ `Thunderline.Datasets.Agent` (correct Ash Resource)

### What Was Fixed
1. Changed resource path in `get_agent/1`
2. Changed resource path in `update_agent_status/3`
3. Added detailed emoji logging (🚀 ✓ ✗ ✅) at each step
4. Created real-time log monitoring script

---

## Complete Test Workflow

1. **Start watching logs:**
   ```bash
   ./watch_training.sh
   ```

2. **In another terminal, open the app:**
   ```bash
   # App is already running at http://localhost:4001
   ```

3. **Create a new agent:**
   - Visit http://localhost:4001/agents/new
   - Name your agent
   - Click "Continue"

4. **Upload documents in each step:**
   - Step 1: Upload `test_sample_document.txt` (in project root)
   - Click "Continue"
   - Step 3: Upload another document or same file
   - Click "Continue"  
   - Step 4: Upload another document or same file
   - Click "Continue"

5. **Watch training happen:**
   - Click "Complete Setup"
   - **Watch the terminal with `./watch_training.sh`**
   - You should see the emoji progress indicators!

6. **Verify success:**
   ```bash
   # Check the CSV was created
   ls -la priv/nfs/agents/*/processed/
   
   # Check job completed
   mix run check_jobs.exs
   ```

---

## Expected Timeline

- Job starts: **Immediate** (when you click "Complete Setup")
- Agent fetch: **< 1 second**
- Document processing: **1-5 seconds** (depends on file count/size)
- CSV creation: **< 1 second**
- Cerebros call: **Variable** (depends on Python execution)
- Total: **Usually 5-15 seconds**

---

## Quick Commands Reference

```bash
# Watch training logs with colors
./watch_training.sh

# Check job status
mix run check_jobs.exs

# Check if server is running
ps aux | grep "mix phx.server" | grep -v grep

# Restart server with logging
pkill -9 beam.smp; sleep 2; mix phx.server 2>&1 | tee /tmp/thunderline_server.log &

# Check CSV files created
find priv/nfs/agents -name "training_data_*.csv"

# Check uploaded files
find priv/nfs/agents -name "*.txt" -o -name "*.pdf" -o -name "*.doc"
```
