# 🧪 Cerebros - Complete Testing Guide

**Date:** October 30, 2025  
**Project:** Cerebros AI Assistant Platform  
**Purpose:** End-to-End Testing with Live NAS Integration

---

## 🎯 Testing Objectives

This guide walks you through testing the complete Cerebros workflow:
1. User authentication (currently bypassed)
2. Dashboard with agent listing
3. 5-step agent creation wizard
4. File uploads with validation
5. Synthetic data generation (NAS integration point)
6. Training pipeline execution (NAS integration point)
7. Agent deployment and readiness

---

## 📋 Pre-Test Checklist

### Environment Setup
- [ ] PostgreSQL running on localhost:5432
- [ ] Elixir 1.19.1 installed
- [ ] Phoenix dependencies installed (`mix deps.get`)
- [ ] Database migrations applied (`mix ecto.migrate`)
- [ ] Test database clean (`MIX_ENV=test mix ecto.reset`)

### Required Services
- [ ] **NAS System** - AI training infrastructure accessible
- [ ] **LLM API** - OpenAI/Anthropic/Azure OpenAI with valid API key
- [ ] **File Storage** - S3/Azure Blob configured (or local for testing)
- [ ] **Email Service** - For magic link authentication (optional for testing)

### Environment Variables
```bash
# Copy .env.example to .env and configure:
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/thunderline_dev"
export SECRET_KEY_BASE="your_secret_key_here"

# LLM API (choose one)
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
# or
export AZURE_OPENAI_ENDPOINT="https://..."
export AZURE_OPENAI_KEY="..."

# File Storage (for production testing)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_S3_BUCKET="cerebros-uploads"
export AWS_REGION="us-east-1"

# NAS Configuration (CRITICAL)
export NAS_API_ENDPOINT="https://your-nas-api.com"
export NAS_API_KEY="your-nas-key"
export NAS_TRAINING_WEBHOOK_URL="http://localhost:4001/api/webhooks/training"
```

---

## 🚀 Quick Start Testing

### 1. Start the Server
```bash
cd /home/mo/thunderline

# Clean start
lsof -ti:4001 -ti:4007 | xargs -r kill -9 2>/dev/null
mix ecto.reset  # Reset DB to clean state
mix phx.server
```

**Expected Output:**
```
[info] Running ThunderlineWeb.Endpoint with Bandit 1.8.0 at http://127.0.0.1:4001
[info] Access ThunderlineWeb.Endpoint at http://localhost:4001
[info] Running LiveDebugger.App.Web.Endpoint with Bandit 1.8.0 at http://127.0.0.1:4007
```

### 2. Verify Server Health
```bash
# Test homepage
curl -I http://localhost:4001/
# Expected: HTTP/1.1 200 OK

# Test dashboard (currently bypasses auth)
curl -I http://localhost:4001/dashboard
# Expected: HTTP/1.1 200 OK

# Test wizard
curl -I http://localhost:4001/agents/new
# Expected: HTTP/1.1 200 OK
```

---

## 🔍 Test Scenarios

### **Test 1: Basic UI Navigation** ✅ (Already Working)

**Steps:**
1. Open browser to `http://localhost:4001`
2. Verify redirect to `/dashboard`
3. Check dashboard loads with:
   - ✅ White background
   - ✅ Cerebros logo
   - ✅ Stats cards (0, 0, --, --%)
   - ✅ Empty state with "Build Your First AI Assistant"
   - ✅ User avatar "MO" in top right
4. Click "Create Your First Assistant"
5. Verify wizard loads at `/agents/new`
6. Check wizard shows:
   - ✅ 5-step progress indicator
   - ✅ Step 1 highlighted
   - ✅ "Upload Work Products" form
   - ✅ File upload drop zone

**Expected Result:** ✅ All UI elements render correctly

---

### **Test 2: File Upload Validation** ✅ (Already Working)

**Prepare Test Files:**
```bash
# Create test directory
mkdir -p /tmp/cerebros_test_files

# Create valid test files
echo "Sample work product content for testing" > /tmp/cerebros_test_files/work_sample.txt
echo "Name,Email,Role\nJohn,john@test.com,Developer" > /tmp/cerebros_test_files/team.csv

# Create large file (should fail - over 50MB)
dd if=/dev/zero of=/tmp/cerebros_test_files/large_file.txt bs=1M count=60

# Create invalid file type (should fail)
echo "invalid" > /tmp/cerebros_test_files/invalid.exe
```

**Test Steps:**
1. Navigate to wizard step 1
2. **Test: Valid file upload**
   - Drag `work_sample.txt` to drop zone
   - ✅ File appears in list with name, size, progress bar
   - ✅ Progress bar fills to 100%
   - ✅ Green checkmark appears
   - ✅ File can be cancelled/removed

3. **Test: Invalid file type**
   - Try uploading `invalid.exe`
   - ✅ Error message: "File type not supported"
   - ✅ File does not appear in list

4. **Test: File too large**
   - Try uploading `large_file.txt` (60MB)
   - ✅ Error message: "File is too large (max 50MB)"
   - ✅ Upload is rejected

5. **Test: Max file limit**
   - Create 11 small files
   - Try uploading all at once
   - ✅ Error: "Too many files (max 10)"
   - ✅ Only first 10 files accepted

6. **Test: Click to browse**
   - Click "Choose Files" button
   - ✅ File picker dialog opens
   - ✅ Selected files upload correctly

**Expected Result:** ✅ All validations work correctly

---

### **Test 3: Agent Creation Workflow** ⚠️ (Partially Working)

**Current Implementation Status:**
- ✅ UI and navigation complete
- ✅ File upload functional
- ⚠️ **File persistence not implemented** - files consumed but not saved
- ⚠️ **Agent creation incomplete** - no user_id association
- ⚠️ **Synthetic data generation stubbed** - returns placeholder data

**Test Steps:**

1. **Step 1: Upload Work Products**
   ```bash
   # From wizard UI:
   - Upload 2-3 sample work products (TXT, PDF, CSV)
   - Click "Continue"
   ```
   
   **Backend Verification:**
   ```elixir
   # In IEx console (iex -S mix phx.server)
   agent = Thunderline.Datasets.Agent |> Ash.read!() |> List.last()
   IO.inspect(agent, label: "Created Agent")
   
   # Check documents (currently returns empty - NOT IMPLEMENTED)
   docs = Thunderline.Datasets.AgentDocument 
     |> Ash.Query.filter(agent_id == ^agent.id)
     |> Ash.read!()
   IO.inspect(docs, label: "Uploaded Documents")
   # Expected: [] (empty - file persistence not implemented)
   ```

2. **Step 2: Review Training Data**
   ```bash
   # Expected behavior:
   - Shows 3 pre-loaded sample examples
   - Each has: Prompt | Reasoning | Output
   - Edit button exists (handler incomplete)
   - Delete button works
   ```
   
   **Test Delete:**
   - Click delete on one example
   - ✅ Example disappears from UI
   - ✅ Remaining examples re-render

3. **Step 3: Upload Communications**
   ```bash
   # Upload sample email/chat logs
   - Same upload functionality as Step 1
   - Click "Continue"
   ```

4. **Step 4: Upload Reference Materials**
   ```bash
   # Upload PDFs, docs, wikis
   - Same upload functionality as Step 1
   - Click "Continue"
   ```

5. **Step 5: Training Progress**
   ```bash
   # Currently shows:
   - 5 training stages
   - All show pending status
   - "Complete Setup" button
   ```
   
   **Expected (when implemented):**
   - Real-time progress updates
   - Stages transition: ○ pending → ● in progress → ✓ completed
   - Training actually executes via NAS

**Expected Result:** 
- ✅ Wizard navigation works
- ⚠️ Files not persisted to storage
- ⚠️ No synthetic data generated
- ⚠️ No training initiated

---

### **Test 4: Synthetic Data Generation** ❌ (NOT IMPLEMENTED - NAS INTEGRATION REQUIRED)

**What Needs to Be Implemented:**

**File:** `lib/thunderline_web/live/agent_creation_wizard_live.ex` (line 196)

```elixir
defp generate_synthetic_work_products(agent_id, uploaded_docs) do
  # TODO: This is currently a placeholder
  # Need to integrate with LLM API (OpenAI/Anthropic)
  
  # REQUIRED IMPLEMENTATION:
  Enum.flat_map(uploaded_docs, fn doc ->
    # 1. Read file content from storage
    file_content = File.read!(doc.file_path)
    
    # 2. Split into chunks if large
    chunks = chunk_text(file_content, max_tokens: 3000)
    
    # 3. Generate synthetic examples per chunk
    Enum.map(chunks, fn chunk ->
      # Call LLM API
      response = call_llm_api(%{
        model: "gpt-4",
        system_prompt: """
        You are an expert at analyzing work products and generating 
        high-quality training examples in the format:
        - User Prompt: What would someone ask to get this output?
        - Reasoning: Step-by-step thinking process
        - Output: The actual deliverable
        """,
        user_content: chunk,
        temperature: 0.7
      })
      
      # 4. Parse LLM response
      %{
        prompt: extract_prompt(response),
        reasoning: extract_reasoning(response),
        output: extract_output(response)
      }
    end)
  end)
end

defp call_llm_api(params) do
  # OpenAI Implementation
  Req.post!("https://api.openai.com/v1/chat/completions",
    json: %{
      model: params.model,
      messages: [
        %{role: "system", content: params.system_prompt},
        %{role: "user", content: params.user_content}
      ],
      temperature: params.temperature
    },
    auth: {:bearer, System.get_env("OPENAI_API_KEY")}
  )
end
```

**Test Steps (After Implementation):**

1. Upload a sample work product document
2. Backend should automatically:
   - Extract text from file
   - Send to LLM API
   - Generate 3-5 synthetic examples per document
   - Store in `agent_documents` table with `is_synthetic: true`

**Verification:**
```elixir
# In IEx
agent_id = "your-agent-uuid"
synthetic_docs = Thunderline.Datasets.AgentDocument
  |> Ash.Query.filter(agent_id == ^agent_id and is_synthetic == true)
  |> Ash.read!()

Enum.each(synthetic_docs, fn doc ->
  IO.puts("Prompt: #{doc.synthetic_prompt}")
  IO.puts("Reasoning: #{doc.synthetic_reasoning}")
  IO.puts("Response: #{doc.synthetic_response}")
  IO.puts("---")
end)
```

**Expected Result:**
- ✅ LLM generates quality examples
- ✅ Examples stored in database
- ✅ Examples appear in Step 2 UI

**NAS Integration Point:**
This is where NAS AI system should be called instead of OpenAI/Anthropic.

---

### **Test 5: Training Pipeline Execution** ❌ (NOT IMPLEMENTED - NAS INTEGRATION REQUIRED)

**What Needs to Be Implemented:**

**File:** `lib/thunderline_web/live/agent_creation_wizard_live.ex` (line 224)

```elixir
defp start_training_pipeline(agent_id) do
  # TODO: Currently just a placeholder that waits 5 seconds per stage
  
  # REQUIRED IMPLEMENTATION:
  # 1. Package all training data
  training_payload = prepare_training_data(agent_id)
  
  # 2. Submit to NAS training API
  case submit_to_nas_training(training_payload) do
    {:ok, training_job_id} ->
      # 3. Store job ID for tracking
      agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
      Ash.update!(agent, %{nas_training_job_id: training_job_id})
      
      # 4. Start polling for updates (or use webhooks)
      schedule_training_status_check(agent_id, training_job_id)
      
    {:error, reason} ->
      # Handle training submission failure
      IO.puts("Training failed to start: #{reason}")
  end
end

defp prepare_training_data(agent_id) do
  # Collect all documents
  docs = Thunderline.Datasets.AgentDocument
    |> Ash.Query.filter(agent_id == ^agent_id)
    |> Ash.read!()
  
  # Group by document type
  %{
    work_products: filter_docs(docs, :work_product),
    qa_pairs: filter_docs(docs, :qa_pair),
    communications: filter_docs(docs, :communication),
    references: filter_docs(docs, :reference),
    synthetic_samples: filter_synthetic(docs)
  }
end

defp submit_to_nas_training(payload) do
  # Call NAS training API
  nas_endpoint = System.get_env("NAS_API_ENDPOINT")
  nas_api_key = System.get_env("NAS_API_KEY")
  
  case Req.post!("#{nas_endpoint}/training/submit",
    json: payload,
    auth: {:bearer, nas_api_key}
  ) do
    %{status: 200, body: %{"job_id" => job_id}} ->
      {:ok, job_id}
    error ->
      {:error, error}
  end
end

defp schedule_training_status_check(agent_id, training_job_id) do
  # Option 1: Polling (simple but less efficient)
  Task.start(fn ->
    poll_training_status(agent_id, training_job_id)
  end)
  
  # Option 2: Webhook (recommended - implement in controller)
  # NAS will call: POST /api/webhooks/training
  # with payload: {agent_id, job_id, status, progress, stage}
end

defp poll_training_status(agent_id, training_job_id, attempt \\ 0) do
  nas_endpoint = System.get_env("NAS_API_ENDPOINT")
  
  case Req.get!("#{nas_endpoint}/training/status/#{training_job_id}") do
    %{status: 200, body: %{"status" => "completed"}} ->
      # Training finished
      agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
      Ash.update!(agent, %{status: :ready, training_progress: 100})
      
      # Broadcast update to LiveView
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "agent:#{agent_id}",
        {:training_complete, agent}
      )
    
    %{status: 200, body: %{"status" => "training", "progress" => progress, "stage" => stage}} ->
      # Update progress
      agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
      Ash.update!(agent, %{
        status: stage_to_atom(stage),
        training_progress: progress
      })
      
      # Broadcast update
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "agent:#{agent_id}",
        {:training_progress, agent}
      )
      
      # Check again in 10 seconds
      :timer.sleep(10_000)
      poll_training_status(agent_id, training_job_id, attempt + 1)
    
    %{status: 200, body: %{"status" => "failed", "error" => error}} ->
      # Training failed
      agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
      Ash.update!(agent, %{status: :training_failed})
      
      Phoenix.PubSub.broadcast(
        Thunderline.PubSub,
        "agent:#{agent_id}",
        {:training_failed, error}
      )
  end
end
```

**Webhook Endpoint (Recommended Approach):**

**Create:** `lib/thunderline_web/controllers/webhook_controller.ex`
```elixir
defmodule ThunderlineWeb.WebhookController do
  use ThunderlineWeb, :controller
  
  def training_update(conn, %{
    "agent_id" => agent_id,
    "job_id" => job_id,
    "status" => status,
    "progress" => progress,
    "stage" => stage
  }) do
    # Verify webhook signature (security)
    case verify_nas_signature(conn) do
      :ok ->
        # Update agent
        agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
        Ash.update!(agent, %{
          status: stage_to_atom(stage),
          training_progress: progress
        })
        
        # Broadcast to LiveView
        Phoenix.PubSub.broadcast(
          Thunderline.PubSub,
          "agent:#{agent_id}",
          {:training_update, %{status: status, progress: progress, stage: stage}}
        )
        
        json(conn, %{status: "ok"})
      
      {:error, :invalid_signature} ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid signature"})
    end
  end
  
  defp verify_nas_signature(conn) do
    # Implement HMAC signature verification
    signature = get_req_header(conn, "x-nas-signature")
    # Compare with expected signature
    :ok
  end
end
```

**Add Route:**
```elixir
# lib/thunderline_web/router.ex
scope "/api/webhooks", ThunderlineWeb do
  pipe_through :api
  
  post "/training", WebhookController, :training_update
end
```

**Test Steps (After Implementation):**

1. **Setup NAS Connection:**
   ```bash
   # Set environment variables
   export NAS_API_ENDPOINT="https://your-nas-api.com"
   export NAS_API_KEY="your-secure-key"
   export NAS_TRAINING_WEBHOOK_URL="http://localhost:4001/api/webhooks/training"
   ```

2. **Create Agent and Upload Files:**
   - Complete steps 1-4 of wizard
   - Upload real documents
   - Proceed to step 5

3. **Verify Training Submission:**
   ```elixir
   # In IEx
   agent_id = "your-agent-uuid"
   agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
   IO.inspect(agent.nas_training_job_id, label: "NAS Job ID")
   # Should have a job ID
   ```

4. **Monitor Training Progress:**
   - Watch Step 5 UI for real-time updates
   - Stages should transition: ○ → ● → ✓
   - Progress percentage should increase
   - Training logs should appear

5. **Verify Completion:**
   ```elixir
   # After training completes
   agent = Ash.get!(Thunderline.Datasets.Agent, agent_id)
   IO.inspect(agent.status, label: "Final Status")
   # Expected: :ready
   
   IO.inspect(agent.training_progress, label: "Progress")
   # Expected: 100
   ```

**Expected Result:**
- ✅ Training submitted to NAS
- ✅ Real-time progress updates
- ✅ Agent transitions through all stages
- ✅ Final status = :ready
- ✅ Model deployed and accessible

**NAS Integration Point:**
This is the core NAS integration - training pipeline execution.

---

### **Test 6: Real-Time Updates with PubSub** ⚠️ (NEEDS IMPLEMENTATION)

**Implementation Required:**

**File:** `lib/thunderline_web/live/agent_creation_wizard_live.ex`

Add to `mount/3`:
```elixir
def mount(_params, _session, socket) do
  # Subscribe to training updates if agent exists
  if connected?(socket) && socket.assigns[:agent] do
    Phoenix.PubSub.subscribe(
      Thunderline.PubSub,
      "agent:#{socket.assigns.agent.id}"
    )
  end
  
  # ... existing code
end
```

Add handler:
```elixir
@impl true
def handle_info({:training_update, update}, socket) do
  agent = Ash.get!(Thunderline.Datasets.Agent, socket.assigns.agent.id)
  
  {:noreply,
   socket
   |> assign(:agent, agent)
   |> put_flash(:info, "Training progress: #{update.progress}%")}
end

@impl true
def handle_info({:training_complete, agent}, socket) do
  {:noreply,
   socket
   |> assign(:agent, agent)
   |> put_flash(:success, "Training complete! Your assistant is ready.")
   |> push_navigate(to: ~p"/dashboard")}
end

@impl true
def handle_info({:training_failed, error}, socket) do
  {:noreply,
   socket
   |> put_flash(:error, "Training failed: #{error}")
   |> assign(:current_step, 5)}
end
```

**Test Steps:**

1. Open wizard in browser
2. Start training process
3. In another terminal, trigger a training update:
   ```elixir
   # In IEx
   agent_id = "your-agent-uuid"
   Phoenix.PubSub.broadcast(
     Thunderline.PubSub,
     "agent:#{agent_id}",
     {:training_update, %{status: "training", progress: 50, stage: "stage3"}}
   )
   ```
4. Verify browser UI updates without refresh
5. Trigger completion:
   ```elixir
   Phoenix.PubSub.broadcast(
     Thunderline.PubSub,
     "agent:#{agent_id}",
     {:training_complete, Ash.get!(Thunderline.Datasets.Agent, agent_id)}
   )
   ```
6. Verify redirect to dashboard

**Expected Result:**
- ✅ UI updates in real-time
- ✅ No page refresh needed
- ✅ Flash messages appear
- ✅ Auto-redirect on completion

---

### **Test 7: Dashboard with Multiple Agents** ⚠️ (NEEDS AGENT LISTING IMPLEMENTATION)

**Implementation Required:**

**File:** `lib/thunderline_web/live/dashboard_live.ex`

```elixir
def mount(_params, _session, socket) do
  # TODO: Get current user and load their agents
  # For now, load all agents (not production ready)
  
  agents = Thunderline.Datasets.Agent
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  
  {:ok,
   socket
   |> assign(:agents, agents)
   |> assign(:agents_empty?, agents == [])}
end
```

**Test Steps:**

1. Create 3-5 agents through wizard with different statuses
2. Return to dashboard
3. Verify agents display with:
   - ✅ Gradient icon badge
   - ✅ Agent name
   - ✅ Status badge (Ready, Processing, Draft)
   - ✅ Created date
   - ✅ Edit/delete buttons

4. Test search (needs implementation):
   ```bash
   # Type in search box
   # Agents filter by name
   ```

5. Test filter (needs implementation):
   ```bash
   # Click filter dropdown
   # Select "Ready" status
   # Only ready agents show
   ```

**Expected Result:**
- ✅ All agents display correctly
- ✅ Status indicators accurate
- ⚠️ Search needs implementation
- ⚠️ Filter needs implementation

---

## 🔄 End-to-End NAS Integration Test

**This is the complete loop test with NAS in production mode.**

### Prerequisites
- ✅ All above implementations complete
- ✅ NAS API accessible and configured
- ✅ Real LLM API credentials set
- ✅ File storage configured
- ✅ Webhook endpoint secured

### Complete Test Flow

```bash
# 1. Clean environment
mix ecto.reset
lsof -ti:4001 | xargs -r kill -9
mix phx.server

# 2. Prepare real test documents
mkdir -p /tmp/cerebros_production_test
cat > /tmp/cerebros_production_test/work_sample.txt << 'EOF'
[Create realistic work product content here - 
could be a technical spec, report, code documentation, etc.]
EOF

cat > /tmp/cerebros_production_test/communication.txt << 'EOF'
[Create realistic email/chat communication examples]
EOF

cat > /tmp/cerebros_production_test/reference.pdf
[Create actual PDF with reference materials]
```

### Test Execution

**Step 1: Create Agent**
1. Navigate to `http://localhost:4001`
2. Click "Create Your First Assistant"
3. Enter assistant name: "Test Assistant Production"
4. Verify agent created in DB:
   ```elixir
   agent = Thunderline.Datasets.Agent |> Ash.read!() |> List.last()
   assert agent.name == "Test Assistant Production"
   assert agent.status == :step1_work_products
   ```

**Step 2: Upload Work Products**
1. Upload `work_sample.txt`
2. Verify file saved to storage (S3/Azure/local)
3. Verify database record:
   ```elixir
   docs = Thunderline.Datasets.AgentDocument
     |> Ash.Query.filter(agent_id == ^agent.id and document_type == :work_product)
     |> Ash.read!()
   
   assert length(docs) == 1
   assert List.first(docs).file_path != nil
   assert File.exists?(List.first(docs).file_path)
   ```

**Step 3: Synthetic Data Generation (NAS Call #1)**
1. Click "Continue" - triggers synthetic generation
2. Monitor logs for LLM API calls
3. Verify synthetic examples created:
   ```elixir
   synthetic = Thunderline.Datasets.AgentDocument
     |> Ash.Query.filter(agent_id == ^agent.id and is_synthetic == true)
     |> Ash.read!()
   
   assert length(synthetic) >= 3
   assert List.first(synthetic).synthetic_prompt != nil
   ```
4. Verify UI displays examples in Step 2

**Step 4: Review Training Data**
1. Verify synthetic examples render correctly
2. Test edit functionality (if implemented)
3. Test delete functionality
4. Click "Continue"

**Step 5: Upload Communications**
1. Upload `communication.txt`
2. Verify storage and DB record
3. Click "Continue"

**Step 6: Upload References**
1. Upload `reference.pdf`
2. Verify storage and DB record
3. Click "Continue"

**Step 7: Training Pipeline (NAS Call #2 - Main Integration)**
1. Step 5 displays training stages
2. Backend calls `start_training_pipeline/1`
3. Training data submitted to NAS
4. Verify NAS job created:
   ```elixir
   agent = Ash.get!(Thunderline.Datasets.Agent, agent.id)
   assert agent.nas_training_job_id != nil
   ```

**Step 8: Monitor Training Progress**
1. Watch for webhook calls from NAS:
   ```bash
   # Check Phoenix logs
   tail -f /tmp/phoenix_4001.log | grep "training_update"
   ```

2. Verify progress updates in UI
3. Verify agent status transitions:
   ```elixir
   # Stage 1
   agent = Ash.get!(Thunderline.Datasets.Agent, agent.id)
   assert agent.status == :stage1_training
   
   # ... through all stages ...
   
   # Final
   assert agent.status == :ready
   assert agent.training_progress == 100
   ```

**Step 9: Verify Completion**
1. UI shows all stages complete (✓)
2. "Complete Setup" button enabled
3. Click button → redirects to dashboard
4. Dashboard shows new agent with "Ready" status

**Step 10: Test Agent Inference** (If API implemented)
```bash
curl -X POST http://localhost:4001/api/agents/{agent_id}/infer \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Test query for the assistant"}'

# Expected: Real response from trained model
```

### Success Criteria

All checks must pass:

- [ ] ✅ Agent created successfully
- [ ] ✅ Files uploaded and stored
- [ ] ✅ Synthetic data generated via LLM
- [ ] ✅ Training submitted to NAS
- [ ] ✅ NAS job ID received
- [ ] ✅ Webhook updates received
- [ ] ✅ Progress bar updates in real-time
- [ ] ✅ All 5 training stages complete
- [ ] ✅ Agent status = :ready
- [ ] ✅ Agent appears on dashboard
- [ ] ✅ Model can be queried for inference
- [ ] ✅ No errors in Phoenix logs
- [ ] ✅ No errors in NAS logs

---

## 🧹 Cleanup After Testing

```bash
# Stop server
pkill -9 beam

# Clean test uploads
rm -rf /tmp/cerebros_test_files
rm -rf /tmp/cerebros_production_test

# Reset database
MIX_ENV=dev mix ecto.reset

# Clear any S3/Azure test files
aws s3 rm s3://cerebros-uploads/test/ --recursive
```

---

## 🐛 Debugging Guide

### Issue: File uploads fail silently
**Check:**
```elixir
# In IEx during upload
Agent.get(:upload_debug, fn state -> state end)
```
**Solution:** Verify `allow_upload/3` configuration and file size limits

### Issue: Synthetic generation fails
**Check:**
```bash
# Verify LLM API key
echo $OPENAI_API_KEY

# Test API directly
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```
**Solution:** Verify API key is valid and has credits

### Issue: Training never starts
**Check:**
```elixir
# Verify NAS endpoint
System.get_env("NAS_API_ENDPOINT")

# Test NAS connection
Req.get!("#{System.get_env("NAS_API_ENDPOINT")}/health")
```
**Solution:** Verify NAS is running and accessible

### Issue: Webhook not receiving updates
**Check:**
```bash
# Verify webhook URL is accessible from NAS
curl -X POST http://localhost:4001/api/webhooks/training \
  -H "Content-Type: application/json" \
  -d '{"agent_id": "test", "status": "test"}'
```
**Solution:** Ensure firewall allows inbound connections, or use ngrok for local testing

### Issue: LiveView doesn't update
**Check:**
```elixir
# Verify PubSub working
Phoenix.PubSub.broadcast(Thunderline.PubSub, "test", {:test, "hello"})
```
**Solution:** Check browser console for WebSocket errors

---

## 📊 Test Metrics & KPIs

Track these metrics during testing:

### Performance
- [ ] Page load time < 2 seconds
- [ ] File upload time < 1 second per MB
- [ ] Synthetic generation < 30 seconds per document
- [ ] Training submission < 5 seconds
- [ ] Real-time update latency < 500ms

### Reliability
- [ ] File upload success rate: 100%
- [ ] LLM API success rate: >95%
- [ ] Training completion rate: 100%
- [ ] Webhook delivery rate: 100%

### Quality
- [ ] Synthetic data quality score: >4/5 (manual review)
- [ ] Model training accuracy: >90% (if metrics available)
- [ ] User experience rating: >4/5

---

## 🚨 Known Limitations & Workarounds

### Current Limitations (October 30, 2025)

1. **No Authentication**
   - All users bypass auth
   - Agents not associated with users
   - **Workaround:** Implement before production

2. **No File Persistence**
   - Files consumed but not saved
   - Can't retrieve uploaded files
   - **Workaround:** Implement storage layer first

3. **Placeholder Synthetic Generation**
   - Returns hardcoded examples
   - No actual LLM calls
   - **Workaround:** Implement LLM integration

4. **No Training Pipeline**
   - Just sleeps 5 seconds per stage
   - No actual model training
   - **Workaround:** Implement NAS integration

5. **No Metrics**
   - Dashboard shows dummy data
   - No real usage tracking
   - **Workaround:** Implement analytics

---

## ✅ Acceptance Criteria for "Done"

The NAS integration loop is complete when:

1. ✅ User can create an agent
2. ✅ User can upload files (stored in S3/Azure)
3. ✅ LLM generates synthetic training data
4. ✅ Training submits to NAS successfully
5. ✅ Progress updates received via webhook
6. ✅ All 5 training stages complete
7. ✅ Agent status becomes "Ready"
8. ✅ Agent appears on dashboard
9. ✅ Model can be queried for inference
10. ✅ Full workflow completes without errors

---

## 📞 Support

**For Issues:**
- Check logs: `tail -f /tmp/phoenix_4001.log`
- Check database: `psql thunderline_dev -c "SELECT * FROM agents;"`
- Check IEx: `iex -S mix phx.server`

**Questions:**
- Refer to `HANDOFF.md` for architecture details
- Check Ash docs: https://hexdocs.pm/ash/
- Phoenix LiveView docs: https://hexdocs.pm/phoenix_live_view/

---

**Good luck testing! 🚀 The NAS integration is the final piece to make this production-ready.**
