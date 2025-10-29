import React, { useState } from "react";

/**
 * UploadFlow - Basic upload demo component
 * 
 * NOTE: The full Cerebros multi-stage upload UI is implemented in the 
 * separate llm-ui frontend repository at /home/mo/llm-ui
 * 
 * This is a minimal placeholder for backend testing purposes.
 * For production, use the React frontend in llm-ui which includes:
 * - Complete 4-stage workflow (Policies, Messages, Prompts, Eval)
 * - Zustand state management
 * - Drag-drop upload with react-dropzone
 * - Progress tracking and retry logic
 * - Proper Cerebros branding and styling
 */
export default function UploadFlow() {
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [preview, setPreview] = useState<any[] | null>(null);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (selectedFile) {
      setFile(selectedFile);
      uploadFile(selectedFile);
    }
  };

  const uploadFile = async (f: File) => {
    setUploading(true);
    setMessage(null);
    const formData = new FormData();
    formData.append("file", f);

    try {
      const res = await fetch("/api/uploads", { method: "POST", body: formData });
      const data = await res.json();
      if (res.ok) {
        setMessage("✓ Upload successful");
        fetchPreview(f.name);
      } else {
        throw new Error(data.message || "Upload failed");
      }
    } catch (e: any) {
      setMessage("✗ Error: " + e.message);
    } finally {
      setUploading(false);
    }
  };

  const fetchPreview = async (filename: string) => {
    try {
      const res = await fetch(`/api/uploads/preview/${filename}`);
      const data = await res.json();
      if (res.ok) {
        setPreview(data.preview);
      } else {
        throw new Error(data.message);
      }
    } catch (e: any) {
      setMessage("Preview error: " + e.message);
    }
  };

  return (
    <div className="max-w-2xl mx-auto mt-12 p-6">
      <h2 className="text-2xl font-bold mb-4">Dataset Upload Test</h2>
      
      <div className="border-2 border-dashed border-gray-300 rounded-lg p-8 mb-4">
        <input
          type="file"
          accept=".csv"
          onChange={handleFileChange}
          className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-violet-50 file:text-violet-700 hover:file:bg-violet-100"
        />
      </div>

      {uploading && <p className="text-blue-600 mb-2">Uploading...</p>}
      {message && <p className="mb-4 font-medium">{message}</p>}

      {preview && (
        <div className="mt-6">
          <h3 className="text-lg font-bold mb-2">CSV Preview</h3>
          <pre className="bg-gray-100 p-4 rounded overflow-auto text-sm max-h-96">
            {JSON.stringify(preview, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}