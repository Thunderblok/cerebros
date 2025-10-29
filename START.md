# 🚀 Cerebros Backend Startup Guide

## Prerequisites
- PostgreSQL running
- Elixir/Erlang installed
- Dependencies installed (`mix deps.get`)
- Database migrations run (`mix ecto.migrate`)

## Quick Start

### 1. Start Backend (Phoenix)
```bash
cd /home/mo/thunderline
mix phx.server
```

The backend will be available at:
- **Main App**: http://localhost:4000
- **LiveDebugger**: http://localhost:4007

### 2. Start Frontend (React)
```bash
cd /home/mo/llm-ui
export VITE_API_URL=http://localhost:4000
npm run dev
```

The frontend will typically run at: http://localhost:3000 or http://localhost:4321 (check terminal output)

## API Endpoints

### Upload File
```bash
curl -X POST http://localhost:4000/api/uploads \
  -F "file=@/path/to/your/file.csv"
```

### Preview CSV
```bash
curl http://localhost:4000/api/uploads/preview/filename.csv
```

## Testing

### Run All Tests
```bash
cd /home/mo/thunderline
mix test
```

### Run Upload Tests Only
```bash
mix test test/thunderline_web/controllers/upload_controller_test.exs
```

## Troubleshooting

### Port 4007 Already in Use
```bash
# Kill process on port 4007
lsof -ti:4007 | xargs kill -9

# Or just kill port 4000 too
lsof -ti:4000 | xargs kill -9
lsof -ti:4007 | xargs kill -9
```

### Database Issues
```bash
# Reset database
mix ecto.reset

# Or just run migrations
mix ecto.migrate
```

### Clean Restart
```bash
# Kill all beam processes
pkill -9 beam

# Start fresh
cd /home/mo/thunderline
mix phx.server
```

## Development Workflow

1. **Backend changes**: Server auto-reloads on file changes
2. **Database changes**: Run `mix ash_postgres.generate_migrations` then `mix ecto.migrate`
3. **Frontend changes**: React will hot-reload automatically

## Project Structure

```
/home/mo/thunderline/           # Phoenix backend (Cerebros API)
├── lib/thunderline/datasets/   # Upload domain & resources
├── lib/thunderline_web/        # Controllers & routes
└── test/                       # Backend tests

/home/mo/llm-ui/               # React frontend (Cerebros UI)
└── apps/www/src/
    └── components/UploadStage/ # Multi-stage upload UI
```

## What's Implemented

✅ Backend API endpoints (`/api/uploads`, `/api/uploads/preview/:filename`)
✅ Database schema for dataset uploads
✅ CSV processing with Explorer
✅ File upload with Ash resource tracking
✅ Frontend 4-stage upload workflow
✅ Zustand state management
✅ Drag-drop file upload
✅ Progress tracking & retry logic
✅ Cerebros branding (#3B1E5E, #1F1F24)

Ready for QA! 🎉
