# 🚀 Cerebros Training System - Quick Start

## ✅ System Ready!

Your standalone Cerebros training system is now set up and ready to use.

## 🎯 Current Status

✅ Multi-stage training pipeline working (all 5 stages)  
✅ API server running on http://localhost:5000  
✅ Test run completed successfully  
✅ Checkpoint system verified  
⏳ React UI needs to be started  

## 🏃 Start Using the System

### API Server (Already Running)

The API server is currently running in your terminal. You should see:
```
Server starting on http://localhost:5000
```

If you need to restart it:
```bash
./start_cerebros.sh
```

### Start the React UI (Required)

Open a **new terminal** and run:
```bash
cd cerebros-core-algorithm-alpha/UI\ REFERENCE
npm install
npm run dev
```

Then open your browser to: **http://localhost:5173**

## 🎨 Using the 5-Step Wizard

1. **Step 1: Upload Work Products**
   - Upload example documents, reports, or files showing your work style

2. **Step 2: Add Training Examples**
   - Add prompt-response pairs (optional)

3. **Step 3: Upload Communications**
   - Upload emails, messages, or communication samples

4. **Step 4: Upload References**
   - Upload reference materials, documentation, or knowledge base files

5. **Step 5: Train & Monitor**
   - Click "Start Training"
   - Watch real-time progress through all 5 stages:
     - 🟣 **Stage 1**: Foundation (base training)
     - 🔵 **Stage 2**: Domain Adaptation
     - 🟢 **Stage 3**: Knowledge Integration
     - 🟡 **Stage 4**: Style Refinement
     - 🔴 **Stage 5**: Personalization

## 📊 What Happens During Training

Each stage:
- Loads the previous checkpoint
- Trains with specific data combinations
- Saves a new checkpoint (.keras file)
- Reports metrics (loss, accuracy, perplexity)
- Takes ~3-5 epochs (currently simulated for demo)

Final result: A fully trained personal assistant model ready for deployment!

## 🧪 Test the Pipeline

You can test the training pipeline directly without the UI:

```bash
./test_cerebros.py
```

This runs a full 5-stage training with synthetic data and shows:
- Real-time progress through all stages
- Metrics at each stage
- Final model location
- All checkpoints saved

## 📁 File Structure

After training, you'll find:

```
priv/nfs/agents/{agent_id}/
├── agent_metadata.json          # Agent info
├── model_metadata.json          # Final model info
├── work_product/                # Uploaded work files
├── communication/               # Uploaded communications
├── reference/                   # Uploaded references
├── processed/                   # Training data CSVs
└── checkpoints/
    ├── stage_1_checkpoint.keras
    ├── stage_1_metadata.json
    ├── stage_2_checkpoint.keras
    ├── stage_2_metadata.json
    ├── stage_3_checkpoint.keras
    ├── stage_3_metadata.json
    ├── stage_4_checkpoint.keras
    ├── stage_4_metadata.json
    ├── stage_5_checkpoint.keras # Final model
    └── stage_5_metadata.json
```

## 🔧 API Endpoints

The API server provides these endpoints:

- `POST /api/agents` - Create new agent
- `POST /api/agents/{id}/documents` - Upload files
- `POST /api/agents/{id}/train` - Start training
- `GET /api/agents/{id}/status` - Get training status
- `GET /api/agents/{id}/results` - Get final results
- `POST /api/agents/{id}/deploy` - Deploy agent
- `POST /api/agents/{id}/chat` - Chat with agent

## 🎯 Next Steps

1. **Start the React UI** (see above)
2. **Create your first agent** through the wizard
3. **Upload your files** in steps 1-4
4. **Start training** and watch the progress
5. **Deploy** when complete!

## 📚 More Information

- Full setup guide: `CEREBROS_STANDALONE_SETUP.md`
- API documentation: See API section in setup guide
- Troubleshooting: Check the "Troubleshooting" section in setup guide

---

**Ready to build your personal AI assistant?** Start the React UI and begin! 🚀
