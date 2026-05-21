defmodule AtomicFi.DocumentParser.Poppler do
  @moduledoc """
  Wrappers around the `poppler-utils` CLI tools (`pdftoppm`,
  `pdftotext`) used by `AtomicFi.DocumentParser` to rasterize PDFs.

  Per repo CLAUDE.md "no graceful fallbacks" — if the binaries
  aren't on PATH we raise. The caller (DocumentParser) reports the
  failure cleanly; we don't paper over it.

  Install: `brew install poppler` (macOS) /
            `apt-get install poppler-utils` (Linux).
  """

  @doc """
  Rasterize each page of `pdf_bytes` to a PNG image.

  Returns `{:ok, [png_bytes, png_bytes, ...]}` in page order, or
  `{:error, reason}` on failure.

  Uses `pdftoppm -png -r <dpi>` (default 150 DPI — readable for
  vision models without producing absurd byte sizes).
  """
  @spec rasterize_pdf(binary(), keyword()) ::
          {:ok, [binary()]} | {:error, term()}
  def rasterize_pdf(pdf_bytes, opts \\ []) when is_binary(pdf_bytes) do
    dpi = Keyword.get(opts, :dpi, 150)

    with :ok <- ensure_binary!("pdftoppm"),
         {:ok, work_dir} <- mkdir_tmp(),
         pdf_path = Path.join(work_dir, "input.pdf"),
         :ok <- File.write(pdf_path, pdf_bytes),
         {:ok, page_paths} <- run_pdftoppm(pdf_path, work_dir, dpi),
         {:ok, pages} <- read_all(page_paths) do
      _ = File.rm_rf(work_dir)
      {:ok, pages}
    else
      {:error, _} = err ->
        err
    end
  end

  @doc """
  Extract the text layer of `pdf_bytes` (no OCR — only embedded text).
  Returns `{:ok, text}` or `{:error, reason}`. Empty text is success.
  """
  @spec text_layer(binary()) :: {:ok, String.t()} | {:error, term()}
  def text_layer(pdf_bytes) when is_binary(pdf_bytes) do
    :ok = ensure_binary!("pdftotext")

    with {:ok, work_dir} <- mkdir_tmp(),
         pdf_path = Path.join(work_dir, "input.pdf"),
         :ok <- File.write(pdf_path, pdf_bytes),
         {text, 0} <-
           System.cmd("pdftotext", ["-layout", pdf_path, "-"], stderr_to_stdout: false) do
      _ = File.rm_rf(work_dir)
      {:ok, text}
    else
      {output, code} when is_integer(code) ->
        {:error, {:pdftotext_failed, code, output}}

      {:error, _} = err ->
        err
    end
  end

  # ── internals ──────────────────────────────────────────────────────

  defp ensure_binary!(name) do
    if System.find_executable(name) do
      :ok
    else
      raise """
      #{name} not found on PATH — install poppler-utils:
        brew install poppler        (macOS)
        apt-get install poppler-utils (Debian/Ubuntu)
      """
    end
  end

  defp mkdir_tmp do
    base =
      System.tmp_dir!() |> Path.join("atomic_fi_parser_#{System.unique_integer([:positive])}")

    File.mkdir_p!(base)
    {:ok, base}
  end

  defp run_pdftoppm(pdf_path, work_dir, dpi) do
    prefix = Path.join(work_dir, "page")
    args = ["-png", "-r", Integer.to_string(dpi), pdf_path, prefix]

    case System.cmd("pdftoppm", args, stderr_to_stdout: true) do
      {_, 0} ->
        # pdftoppm names files <prefix>-1.png, <prefix>-2.png, etc.
        # for multi-page; for a single-page PDF some builds emit
        # <prefix>.png. Pick up either shape and sort numerically.
        pages =
          work_dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".png"))
          |> Enum.sort_by(&page_index/1)
          |> Enum.map(&Path.join(work_dir, &1))

        if pages == [] do
          {:error, :pdftoppm_produced_no_pages}
        else
          {:ok, pages}
        end

      {output, code} ->
        {:error, {:pdftoppm_failed, code, output}}
    end
  end

  defp page_index(filename) do
    case Regex.run(~r/-(\d+)\.png$/, filename) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp read_all(paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case File.read(path) do
        {:ok, bytes} -> {:cont, {:ok, [bytes | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end
end
