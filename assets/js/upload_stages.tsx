import React, { useState } from "react";
import { Upload, StageIndicator, MessageList } from "llm-ui";

/**
 * UploadFlow handles the 4-stage dataset uploading process:
 * 1. File selection
 * 2. Upload progress
 * 3. Semantic labeling
 * 4. Data preview
 */
export default function UploadFlow() {
  const [stage, setStage] = useState(1);
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [preview, setPreview] = useState<any[] | null>(null);

  const handleFile = (f: File) => {
    setFile(f);
    setStage(2);
    uploadFile(f);
  };

  const uploadFile = async (f: File) => {
    setUploading(true);
    const formData = new FormData();
    formData.append("file", f);

    try {
      const res = await fetch("/api/uploads", { method: "POST", body: formData });
      const data = await res.json();
      if (res.ok) {
        setMessage("Upload successful");
        setStage(3);
        fetchPreview(f.name);
      } else {
        throw new Error(data.message || "Upload failed");
      }
    } catch (e: any) {
      setMessage(e.message);
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
        setStage(4);
      } else {
        throw new Error(data.message);
      }
    } catch (e: any) {
      setMessage(e.message);
    }
  };

  return (
    <div className="max-w-2xl mx-auto mt-12">
      <StageIndicator totalStages={4} currentStage={stage} />
      {stage === 1 && <Upload onFileSelect={handleFile} />}
      {stage === 2 && <MessageList messages={[uploading ? "Uploading..." : message || "Idle"]} />}
      {stage === 3 && <MessageList messages={["Performing semantic labeling... (TBD)"]} />}
      {stage === 4 && (
        <div className="mt-6">
          <h3 className="text-lg font-bold mb-2">CSV Preview</h3>
          <pre className="bg-gray-100 p-4 rounded overflow-auto text-sm">
            {JSON.stringify(preview, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}