#!/bin/bash
# Quick Start Script for Cerebros Standalone Training System

echo "================================================"
echo "  Cerebros Multi-Stage Training System"
echo "  Standalone Demo"
echo "================================================"
echo ""

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "📦 Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Check if Flask is installed
if ! python -c "import flask" 2>/dev/null; then
    echo "📦 Installing Python dependencies..."
    pip install flask flask-cors pandas numpy
fi

# Ensure NFS directory exists
mkdir -p priv/nfs/agents

echo ""
echo "🚀 Starting Cerebros Training API Server..."
echo "   Server will be available at: http://localhost:5000"
echo ""
echo "📝 To use the system:"
echo "   1. Keep this terminal open (API server)"
echo "   2. Open another terminal and run:"
echo "      cd cerebros-core-algorithm-alpha/UI\\ REFERENCE"
echo "      npm install"
echo "      npm run dev"
echo "   3. Open browser to http://localhost:5173"
echo ""
echo "================================================"
echo ""

# Start the API server
python cerebros-core-algorithm-alpha/training_api_server.py
