# File Upload Testing

## Test the Local NFS Upload Feature

### Quick Test Commands

```bash
# 1. Create a test agent in the database
cd /home/mo/thunderline
iex -S mix phx.server

# In IEx console:
{:ok, agent} = Ash.create(Thunderline.Datasets.Agent, %{
  name: "Test Agent",
  status: :step1_work_products,
  current_step: 1
})

agent.id  # Copy this UUID
```

### Manual Browser Test

1. **Navigate to the wizard:**
   - Go to `http://localhost:4001/agents/new`
   - You should see Step 1: Upload Work Products

2. **Create test files:**
   ```bash
   # Create test files
   mkdir -p /tmp/test_uploads
   echo "This is a test work product document" > /tmp/test_uploads/sample.txt
   echo "Name,Role,Email
   John Doe,Developer,john@example.com
   Jane Smith,Designer,jane@example.com" > /tmp/test_uploads/team.csv
   ```

3. **Upload files:**
   - Drag and drop files OR click "Choose Files"
   - Files should show in the list with progress bars
   - Click the file upload form's submit or the "Continue" button
   - Check flash message: "X file(s) uploaded successfully to local NFS!"

4. **Verify files were saved:**
   ```bash
   # Check the NFS directory structure
   ls -la /home/mo/thunderline/priv/nfs/agents/
   
   # Should see a directory with the agent's UUID
   # Navigate into it:
   ls -la /home/mo/thunderline/priv/nfs/agents/{agent-uuid}/work_product/
   
   # You should see your uploaded files:
   # - sample.txt
   # - team.csv
   ```

5. **Verify database records:**
   ```bash
   # In IEx console:
   docs = Thunderline.Datasets.AgentDocument 
     |> Ash.Query.filter(agent_id == ^agent.id)
     |> Ash.read!()
   
   Enum.each(docs, fn doc ->
     IO.puts("File: #{doc.original_filename}")
     IO.puts("Path: #{doc.file_path}")
     IO.puts("Type: #{doc.document_type}")
     IO.puts("Status: #{doc.status}")
     IO.puts("---")
   end)
   ```

### Expected Results

✅ **File System:**
- Files saved to: `priv/nfs/agents/{agent_id}/work_product/`
- Original filenames preserved
- Files readable and intact

✅ **Database:**
- `agent_documents` table has records
- `file_path` points to correct location
- `document_type` = `:work_product` for step 1
- `status` = `:uploaded`
- `is_synthetic` = `false`

✅ **UI:**
- Flash message confirms upload
- Files appear in upload list
- Can proceed to next step

### Test Different Steps

**Step 3 - Communications:**
- Navigate to step 3
- Upload email/chat samples
- Files saved to: `priv/nfs/agents/{agent_id}/communication/`

**Step 4 - References:**
- Navigate to step 4
- Upload reference PDFs/docs
- Files saved to: `priv/nfs/agents/{agent_id}/reference/`

### Cleanup Test Data

```bash
# Remove test files
rm -rf /home/mo/thunderline/priv/nfs/agents/{test-agent-uuid}

# Clean database
iex -S mix phx.server

# In IEx:
agent = Ash.get!(Thunderline.Datasets.Agent, "your-test-agent-uuid")
Ash.destroy!(agent)
```

## File Upload Feature Summary

### ✅ What's Working Now:

1. **File Upload to Local NFS:**
   - Files are saved to `priv/nfs/agents/{agent_id}/{document_type}/`
   - Original filenames preserved
   - Directory structure automatically created

2. **Database Integration:**
   - Each uploaded file gets a record in `agent_documents` table
   - Tracks: file path, original name, type, status, timestamps

3. **Multi-Step Support:**
   - Step 1: work_product files
   - Step 3: communication files
   - Step 4: reference files

4. **Validation:**
   - File type validation (8 supported formats)
   - File size limit: 50MB per file
   - Max files per upload: 10 files

### 🔄 Next Steps for Production:

1. **Add file retrieval endpoint**
2. **Implement file deletion when agent is deleted**
3. **Add virus scanning for uploads**
4. **Migrate to cloud storage (S3/Azure) for production**
5. **Implement file compression for large files**
6. **Add file preview functionality**

---

**Date:** October 30, 2025  
**Feature:** Local NFS File Upload Implementation  
**Status:** ✅ Complete and Working
