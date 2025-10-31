# Thunderline Training Pipeline

## Overview

The Thunderline training pipeline processes uploaded documents and trains AI agents using the Cerebros NAS framework. The pipeline automatically triggers when users complete Step 4 (upload all required documents) and navigate to Step 5 (final review).

## Architecture

```
┌─────────────────┐
│   User uploads  │
│   documents in  │
│   Steps 1-4     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│  Step 4 → 5 transition      │
│  (next_step handler)         │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Enqueue Oban Job           │
│  CerebrosTrainingWorker     │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Process Documents          │
│  - Extract text from files  │
│  - Convert to CSV           │
│  - Chunk into 512 chars     │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Send to Cerebros via RPC   │
│  - Call Python wrapper      │
│  - Pass CSV + config        │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Cerebros NAS Training      │
│  - Neural Architecture Search│
│  - Train text generation    │
│  - Save trained model       │
└─────────────────────────────┘
```

## Components

### 1. Document Processor (`lib/thunderline/document_processor.ex`)

Handles document processing with support for multiple formats:

- **Text Extraction**:
  - `.txt` files: Direct read
  - `.pdf` files: Uses `pdftotext` (poppler-utils)
  - `.docx` files: Unzips and parses XML

- **Chunking**: Splits text into 512-character segments with 50-character overlap for context

- **CSV Conversion**: Exports chunks with metadata (document ID, type, filename, chunk index)

**Key Functions**:
```elixir
# Process all documents for an agent
DocumentProcessor.process_agent_documents(agent_id)

# Convert to CSV
DocumentProcessor.to_csv(chunks)

# Write to file
DocumentProcessor.write_csv(chunks, output_path)
```

### 2. Oban Worker (`lib/thunderline/workers/cerebros_training_worker.ex`)

Asynchronous job worker that orchestrates the training pipeline:

**Queue**: `:cerebros_training`
**Max Attempts**: 3

**Job Flow**:
1. Fetch agent record
2. Process and chunk all uploaded documents
3. Save chunks to CSV in `priv/nfs/agents/{agent_id}/processed/`
4. Call Cerebros Python wrapper via System.cmd
5. Update agent training status

**Key Functions**:
```elixir
# Enqueue a training job
%{agent_id: agent_id} 
|> CerebrosTrainingWorker.new() 
|> Oban.insert()
```

### 3. Cerebros Wrapper (`cerebros-core-algorithm-alpha/train_model_wrapper.py`)

Python script that bridges Thunderline and Cerebros:

**Input**: JSON payload file containing:
- `agent_id`: UUID of the agent
- `agent_name`: Display name
- `csv_path`: Path to training CSV
- `model_config`: Training hyperparameters

**Output**: Training results JSON with:
- Training status
- Output directory
- Chunk count
- Model configuration
- Timestamp

**Usage**:
```bash
python3 train_model_wrapper.py payload.json
```

### 4. LiveView Handler (`lib/thunderline_web/live/agent_creation_wizard_live.ex`)

Updated `next_step` handler triggers training when moving from step 4 to 5:

```elixir
def handle_event("next_step", _params, socket) do
  current_step = socket.assigns.current_step
  next_step = min(5, current_step + 1)
  
  socket = if next_step == 5 and current_step == 4 do
    start_training_pipeline(socket)
  else
    socket
  end
  
  {:noreply, socket |> assign(:current_step, next_step) |> ...}
end
```

## File Structure

```
priv/nfs/agents/{agent_id}/
├── work_product/           # Step 1 uploads
├── communication/          # Step 3 uploads
├── reference/              # Step 4 uploads
└── processed/
    └── training_data_{timestamp}.csv
```

## Configuration

### Environment Variables

- `PYTHON_PATH`: Path to Python 3 executable (default: `python3`)

### Oban Queue

Add to `config/config.exs`:

```elixir
config :thunderline, Oban,
  queues: [
    default: 10,
    cerebros_training: 5  # Add this queue
  ]
```

## Dependencies

### Elixir/Phoenix
- `oban` - Job processing
- `ash_csv` - CSV handling
- `explorer` - Data manipulation

### System Tools
- `pdftotext` (poppler-utils) - For PDF text extraction
- Python 3 - For Cerebros integration

Install PDF tools:
```bash
# Ubuntu/Debian
sudo apt-get install poppler-utils

# macOS
brew install poppler
```

### Python Dependencies
Install Cerebros requirements:
```bash
cd cerebros-core-algorithm-alpha
pip install -r requirements.txt
```

## Usage

### For End Users

1. Navigate to `/agents/new`
2. Upload documents in Steps 1, 3, and 4
3. Click "Next Step" on Step 4
4. Training automatically initiates
5. Review training status on Step 5

### For Developers

**Manually trigger training**:
```elixir
# In IEx
%{agent_id: "your-agent-uuid"}
|> Thunderline.Workers.CerebrosTrainingWorker.new()
|> Oban.insert()
```

**Process documents directly**:
```elixir
chunks = Thunderline.DocumentProcessor.process_agent_documents(agent_id)
Thunderline.DocumentProcessor.write_csv(chunks, "/tmp/training.csv")
```

**Monitor Oban jobs**:
```elixir
# List all training jobs
Oban.Job
|> Oban.Query.where(worker: "Thunderline.Workers.CerebrosTrainingWorker")
|> Repo.all()
```

## Testing

### Test Document Processing

```elixir
# Create test document
agent = create_test_agent()
doc = create_test_document(agent.id, "test.txt", "Sample text content")

# Process
chunks = Thunderline.DocumentProcessor.process_agent_documents(agent.id)

# Verify
assert length(chunks) > 0
assert Enum.all?(chunks, &(String.length(&1.text) <= 512))
```

### Test Oban Worker

```elixir
# Enqueue job
{:ok, job} = %{agent_id: agent.id}
  |> CerebrosTrainingWorker.new()
  |> Oban.insert()

# Manually execute
Oban.drain_queue(queue: :cerebros_training)

# Check results
assert job.state == "completed"
```

## Troubleshooting

### Common Issues

**PDF extraction fails**:
- Ensure `pdftotext` is installed: `which pdftotext`
- Check PDF is not encrypted or corrupted

**DOCX extraction fails**:
- Verify file is valid DOCX (ZIP archive)
- Check for corrupted XML structure

**Oban job fails**:
- Check logs in `log/dev.log`
- Verify Python script is executable: `ls -l cerebros-core-algorithm-alpha/train_model_wrapper.py`
- Test Python script manually: `python3 train_model_wrapper.py test_payload.json`

**Agent status not updating**:
- Verify agent has `update` action defined
- Check Ash policies allow updates
- Ensure `training_progress` field exists and is map type

## Future Enhancements

- [ ] Real-time progress updates via PubSub
- [ ] Streaming training metrics to UI
- [ ] Distributed training across multiple nodes
- [ ] Model versioning and rollback
- [ ] A/B testing of model variants
- [ ] Integration with MLflow for experiment tracking
- [ ] Automated hyperparameter optimization
- [ ] GPU/TPU acceleration
- [ ] Model quantization for deployment

## License

See LICENSE file for details.
