"""Use the packaged DOCX rasterizer with native Word PDF conversion on Windows."""
from pathlib import Path
import importlib.util
import os
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEPENDENCIES = Path("C:/Users/carzy/.cache/codex-runtimes/codex-primary-runtime/dependencies")
HELPER = Path("C:/Users/carzy/.codex/plugins/cache/openai-primary-runtime/documents/26.905.11957/skills/documents/render_docx.py")


def native_word_pdf(doc_path, user_profile, convert_tmp_dir, stem, verbose):
    output = Path(convert_tmp_dir) / (stem + ".pdf")
    command = ["C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
        "-File", str(ROOT / "tools/legal/export_docx_pdf.ps1"), "-SourcePath", str(Path(doc_path).resolve()), "-PdfPath", str(output)]
    result = subprocess.run(command, capture_output=True, timeout=180, creationflags=subprocess.CREATE_NO_WINDOW)
    diagnostic = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    if result.returncode != 0 or not output.is_file():
        return "", diagnostic
    if verbose: print(diagnostic)
    return str(output), "Native Microsoft Word COM PDF conversion. " + diagnostic


def main():
    poppler = next((DEPENDENCIES / "native/poppler").rglob("pdfinfo.exe"))
    os.environ["PATH"] = str(poppler.parent) + os.pathsep + os.environ.get("PATH", "")
    spec = importlib.util.spec_from_file_location("packaged_document_renderer", HELPER)
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    # Only replace the unavailable LibreOffice conversion; retain canonical PNG QA.
    renderer.convert_to_pdf = native_word_pdf
    renderer.main()


if __name__ == "__main__":
    main()
