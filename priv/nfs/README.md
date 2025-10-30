# NFS Storage Directory

This directory stores uploaded files locally for the Cerebros application.

## Structure

```
priv/nfs/agents/
└── {agent_id}/
    ├── work_product/       # Step 1: Work product documents
    ├── communication/      # Step 3: Communication examples
    └── reference/          # Step 4: Reference materials
```

## File Organization

Each agent has a separate directory identified by their UUID. Within each agent directory, files are organized by document type:

- **work_product**: Documents uploaded in Step 1 (reports, deliverables, etc.)
- **communication**: Communication examples uploaded in Step 3 (emails, chats, etc.)
- **reference**: Reference materials uploaded in Step 4 (PDFs, documentation, etc.)

## Database Records

Each uploaded file has a corresponding record in the `agent_documents` table with:
- `agent_id`: Links to the agent
- `document_type`: The type of document (work_product, communication, reference)
- `file_path`: Absolute path to the file in this NFS storage
- `original_filename`: Original name of the uploaded file
- `status`: Upload status (uploaded, processing, completed, etc.)
- `is_synthetic`: Whether this is a generated synthetic example

## Storage Limits

- Maximum file size: 50MB per file
- Maximum files per upload: 10 files
- Supported formats: .txt, .pdf, .doc, .docx, .csv, .json, .xml, .md

## Cleanup

This directory is excluded from git via .gitignore. Files are stored persistently and should be cleaned up when agents are deleted.

## Production Deployment

For production, consider migrating to cloud storage:
- AWS S3
- Azure Blob Storage
- Google Cloud Storage

The file upload handler can be easily modified to use cloud storage SDKs instead of local filesystem operations.
