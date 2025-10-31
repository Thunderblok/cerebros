# 🎯 TRAINING MONITORING - COMPLETE SETUP

## What We Fixed

### The Problem
Training jobs were **failing silently** and you couldn't see what was happening.

### Root Causes
1. **Wrong Module Path**: Worker used `Thunderline.Agents.Agent` instead of `Thunderline.Datasets.Agent`
2. **No Visibility**: No way to see training progress in real-time
3. **Poor Logging**: Hard to debug when things went wrong

### Solutions Implemented
1. ✅ Fixed resource path to correct Ash Resource
2. ✅ Added emoji-based step-by-step logging (🚀 ✓ ✗ ✅)
3. ✅ Created `watch_training.sh` for real-time monitoring
4. ✅ Server logs now piped to `/tmp/thunderline_server.log`
5. ✅ Enhanced error messages at each pipeline stage

---

## How to Monitor Training (3 Ways)

### Method 1: Real-Time Log Watching (RECOMMENDED)
```bash
./watch_training.sh
```

**What you'll see:**
```
🚀 Starting Cerebros training for agent abc-123...
✓ Agent fetched: {:ok, %Thunderline.Datasets.Agent{...}}
✓ Processed 12 chunks
✓ CSV saved to priv/nfs/agents/abc-123/processed/training_data_1234567890.csv
✓ Cerebros training initiated successfully
✅ Training pipeline complete for agent abc-123
```

**Advantages:**
- See exactly what's happening in real-time
- Color-coded output (green = success, red = error, yellow = info)
- No database queries needed
- Instant feedback

**When to use:** Always! Run this in a separate terminal before starting training.

---

### Method 2: Job Status Check
```bash
mix run check_jobs.exs
```

**What you'll see:**
```
=== OBAN JOBS SUMMARY ===
Total jobs: 3
  completed: 3

=== RECENT JOBS (Last 10) ===
Job #3
   Worker: Thunderline.Workers.CerebrosTrainingWorker
   Queue: cerebros_training
   State: completed
   Agent ID: abc-123
   Attempt: 1/3
   Inserted: 2025-10-30 22:45:00
   Completed: 2025-10-30 22:45:15
```

**Advantages:**
- Historical view of all jobs
- See error details for failed jobs
- Check job state (executing, completed, discarded)

**When to use:** After training to verify completion or troubleshoot failures.

---

### Method 3: Raw Server Logs
```bash
tail -f /tmp/thunderline_server.log
```

**Advantages:**
- See ALL server activity
- Useful for debugging other issues

**Disadvantages:**
- Very verbose (includes DB queries, HTTP requests, etc.)
- Hard to find training-related messages

**When to use:** Deep debugging when other methods don't show the issue.

---

## Complete Testing Workflow

### Terminal 1: Start Log Monitoring
```bash
cd /home/mo/thunderline
./watch_training.sh
```

Leave this running! You'll see training progress here.

### Terminal 2: Test the System

1. **Verify server is running:**
   ```bash
   ps aux | grep "mix phx.server" | grep -v grep
   ```
   
   Should show one running process. If not:
   ```bash
   pkill -9 beam.smp; sleep 2
   mix phx.server 2>&1 | tee /tmp/thunderline_server.log &
   ```

2. **Open the app:**
   ```
   http://localhost:4001
   ```

3. **Create new agent:**
   - Click "Build your first AI assistant"
   - Give it a name
   - Click "Continue"

4. **Step 1 - Upload work product:**
   - Upload `test_sample_document.txt` (in project root)
   - Click "Continue"

5. **Step 2 - Name & Personality:**
   - Fill in or skip
   - Click "Continue"

6. **Step 3 - Upload communication:**
   - Upload `test_sample_document.txt` again
   - Click "Continue"

7. **Step 4 - Upload reference:**
   - Upload `test_sample_document.txt` again
   - Click "Continue"

8. **Step 5 - Training:**
   - Click "Complete Setup"
   - **LOOK AT TERMINAL 1** - You should see training progress!

9. **Verify in Terminal 2:**
   ```bash
   # Check job completed
   mix run check_jobs.exs
   
   # Check CSV created
   ls -la priv/nfs/agents/*/processed/
   
   # Check uploaded files
   ls -la priv/nfs/agents/*/work_products/
   ```

---

## What Success Looks Like

### In watch_training.sh Terminal:
```
🚀 Starting Cerebros training for agent 9e784739-e6e9-4231-b23f-748d33a10c78
✓ Agent fetched: {:ok, ...}
✓ Processed 15 chunks
✓ CSV saved to priv/nfs/agents/9e784739-e6e9-4231-b23f-748d33a10c78/processed/training_data_1730329500.csv
✓ Cerebros training initiated successfully
✅ Training pipeline complete for agent 9e784739-e6e9-4231-b23f-748d33a10c78
```

### In check_jobs.exs:
```
Job #1
   Worker: Thunderline.Workers.CerebrosTrainingWorker
   State: completed
   Attempt: 1/3
   Errors: []
```

### In File System:
```bash
$ ls priv/nfs/agents/*/processed/
training_data_1730329500.csv

$ ls priv/nfs/agents/*/work_products/
test_sample_document.txt
```

---

## Troubleshooting

### "Nothing appears in watch_training.sh"

**Possible causes:**
1. Server not logging to `/tmp/thunderline_server.log`
2. Job hasn't started yet
3. Job failed immediately

**Fix:**
```bash
# Check if log file exists
ls -la /tmp/thunderline_server.log

# Check if server is logging
tail /tmp/thunderline_server.log

# Check job status
mix run check_jobs.exs
```

---

### "Jobs show as 'discarded' with errors"

**Check the error:**
```bash
mix run check_jobs.exs | grep -A 20 "Errors:"
```

**Common errors:**

1. **"Expected an `Ash.Resource`"**
   - Should be fixed now
   - If you still see this, the server didn't restart
   - Fix: `pkill -9 beam.smp; sleep 2; mix phx.server &`

2. **"Agent not found"**
   - Agent ID is wrong
   - Database issue

3. **"Document processing failed"**
   - Files couldn't be read
   - Check: `ls -la priv/nfs/agents/*/`

4. **"CSV write failed"**
   - Permission issue
   - Fix: `chmod -R 755 priv/nfs/`

5. **"Cerebros call failed"**
   - Python script issue
   - Check: `chmod +x cerebros-core-algorithm-alpha/train_model_wrapper.py`
   - Check: `python3 --version`

---

### "Training seems stuck"

**Check if job is executing:**
```bash
mix run check_jobs.exs | grep "executing"
```

If stuck for > 5 minutes, something is wrong.

**Force restart:**
```bash
# Kill server
pkill -9 beam.smp

# Clear stuck jobs
mix run -e 'Thunderline.Repo.query!("DELETE FROM oban_jobs WHERE state = '\''executing'\''"); System.halt(0)'

# Restart
mix phx.server 2>&1 | tee /tmp/thunderline_server.log &
```

---

## Files Created by This Fix

1. **`watch_training.sh`** - Real-time log monitoring script
2. **`check_jobs.exs`** - Oban job status checker
3. **`MONITORING_GUIDE.md`** - Detailed monitoring guide
4. **`HOW_TO_MONITOR_JOBS.md`** - Job monitoring reference
5. **`THIS FILE`** - Complete setup guide

---

## Quick Reference

```bash
# Watch training in real-time
./watch_training.sh

# Check job status
mix run check_jobs.exs

# Restart server with logging
pkill -9 beam.smp; sleep 2; mix phx.server 2>&1 | tee /tmp/thunderline_server.log &

# Check CSV files
find priv/nfs/agents -name "*.csv"

# Check uploaded files  
find priv/nfs/agents -type f ! -name "*.csv"

# Clear all jobs (nuclear option)
mix run -e 'Thunderline.Repo.query!("TRUNCATE oban_jobs"); System.halt(0)'
```

---

## Summary

**Before:** Training failed silently, no visibility

**After:** 
- ✅ Training works correctly
- ✅ Real-time monitoring available
- ✅ Clear emoji-based progress indicators
- ✅ Multiple ways to check status
- ✅ Comprehensive troubleshooting guides

**To test:** Run `./watch_training.sh` in one terminal, then create a new agent in the browser and upload files. You'll see the training progress live!
