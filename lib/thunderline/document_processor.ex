defmodule Thunderline.DocumentProcessor do
  @moduledoc """
  Handles processing of uploaded documents: conversion to CSV and chunking for training.
  """

  require Logger
  require Ash.Query

  @chunk_size 512

  @doc """
  Processes all documents for an agent:
  1. Converts documents to CSV format
  2. Chunks text into #{@chunk_size}-character segments
  3. Returns chunked data ready for training
  """
  def process_agent_documents(agent_id) do
    Logger.info("Processing documents for agent #{agent_id}")

    agent_id
    |> get_agent_documents()
    |> Enum.map(&process_document/1)
    |> List.flatten()
    |> chunk_texts()
  end

  @doc """
  Processes a single document: extracts text and converts to CSV-compatible format
  """
  def process_document(%{file_path: file_path, document_type: doc_type} = document) do
    Logger.info("Processing document: #{file_path}, type: #{doc_type}")

    case extract_text(file_path, doc_type) do
      {:ok, text} ->
        %{
          document_id: document.id,
          document_type: doc_type,
          file_name: Path.basename(file_path),
          text: text,
          char_count: String.length(text)
        }

      {:error, reason} ->
        Logger.error("Failed to extract text from #{file_path}: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Extracts text from a file based on its type
  """
  def extract_text(file_path, document_type) do
    case document_type do
      "text" ->
        extract_text_from_txt(file_path)

      "pdf" ->
        extract_text_from_pdf(file_path)

      "docx" ->
        extract_text_from_docx(file_path)

      _ ->
        {:error, :unsupported_format}
    end
  end

  @doc """
  Extracts text from a plain text file
  """
  def extract_text_from_txt(file_path) do
    case File.read(file_path) do
      {:ok, content} -> {:ok, content}
      error -> error
    end
  end

  @doc """
  Extracts text from a PDF file using external tools
  For now, we'll use pdftotext (part of poppler-utils)
  """
  def extract_text_from_pdf(file_path) do
    # Try using pdftotext command
    case System.cmd("pdftotext", [file_path, "-"], stderr_to_stdout: true) do
      {text, 0} ->
        {:ok, text}

      {error, _code} ->
        Logger.warning("pdftotext failed: #{error}")
        {:error, :pdf_extraction_failed}
    end
  rescue
    e ->
      Logger.error("PDF extraction error: #{inspect(e)}")
      {:error, :pdf_tool_not_available}
  end

  @doc """
  Extracts text from a DOCX file
  DOCX files are ZIP archives containing XML. We extract the document.xml file.
  """
  def extract_text_from_docx(file_path) do
    try do
      # DOCX files are ZIP archives
      case :zip.unzip(String.to_charlist(file_path), [:memory]) do
        {:ok, files} ->
          # Find word/document.xml
          case Enum.find(files, fn {name, _} -> name == ~c"word/document.xml" end) do
            {_, xml_content} ->
              # Simple XML text extraction - remove all tags
              text =
                xml_content
                |> to_string()
                |> String.replace(~r/<[^>]+>/, " ")
                |> String.replace(~r/\s+/, " ")
                |> String.trim()

              {:ok, text}

            nil ->
              {:error, :document_xml_not_found}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("DOCX extraction error: #{inspect(e)}")
        {:error, :docx_extraction_failed}
    end
  end

  @doc """
  Chunks texts into #{@chunk_size}-character segments with overlap
  """
  def chunk_texts(documents) do
    documents
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&chunk_document/1)
  end

  @doc """
  Chunks a single document into #{@chunk_size}-character segments
  """
  def chunk_document(%{text: text, document_id: doc_id} = doc_data) do
    # Split into chunks with 50-character overlap for context
    overlap = 50
    step = @chunk_size - overlap

    text
    |> String.graphemes()
    |> Enum.chunk_every(@chunk_size, step, :discard)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, idx} ->
      %{
        chunk_id: "#{doc_id}_chunk_#{idx}",
        document_id: doc_id,
        document_type: doc_data.document_type,
        file_name: doc_data.file_name,
        chunk_index: idx,
        text: Enum.join(chunk, ""),
        char_count: length(chunk)
      }
    end)
  end

  @doc """
  Converts chunked data to CSV format for training
  """
  def to_csv(chunks) do
    headers = ["chunk_id", "document_id", "document_type", "file_name", "chunk_index", "text", "char_count"]

    rows =
      Enum.map(chunks, fn chunk ->
        [
          chunk.chunk_id,
          chunk.document_id,
          chunk.document_type,
          chunk.file_name,
          chunk.chunk_index,
          chunk.text,
          chunk.char_count
        ]
      end)

    {:ok, [headers | rows]}
  end

  @doc """
  Writes chunks to a CSV file
  """
  def write_csv(chunks, output_path) do
    case to_csv(chunks) do
      {:ok, csv_data} ->
        csv_content =
          csv_data
          |> Enum.map(&Enum.join(&1, ","))
          |> Enum.join("\n")

        File.write(output_path, csv_content)

      error ->
        error
    end
  end

  # Private helper to get all documents for an agent
  defp get_agent_documents(agent_id) do
    Thunderline.Datasets.AgentDocument
    |> Ash.Query.filter(agent_id: agent_id)
    |> Ash.read!()
  end
end
