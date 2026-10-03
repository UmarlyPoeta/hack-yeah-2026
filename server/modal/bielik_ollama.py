"""Bielik-4.5B-v3.0-Instruct behind an Ollama-compatible API on Modal (GPU).

server/ talks to it exactly like a local Ollama: set OLLAMA_URL to the URL printed by
`modal deploy` and send the proxy-auth headers Modal-Key / Modal-Secret (see README.md).

Deploy:     modal deploy server/modal/bielik_ollama.py
Demo mode:  BIELIK_MIN_CONTAINERS=1 modal deploy server/modal/bielik_ollama.py   (no cold starts, billed while idle)
"""
import os
import subprocess
import threading
import time
import urllib.request

import modal

HF_REPO = "speakleash/Bielik-4.5B-v3.0-Instruct-GGUF"
GGUF_FILE = "Bielik-4.5B-v3.0-Instruct.Q8_0.gguf"  # the official repo ships only Q8_0 and fp16; Q8_0 fits any GPU easily
MODEL_NAME = "bielik-4.5b-v3.0-instruct:Q8_0"  # = LLM_MODEL in server/.env

OLLAMA_PORT = 11434
GPU = os.environ.get("BIELIK_GPU", "T4")  # cheapest Modal GPU; 16 GB VRAM is plenty for Q8_0
MIN_CONTAINERS = int(os.environ.get("BIELIK_MIN_CONTAINERS", "0"))

# ChatML, as stored in the GGUF metadata (tokenizer.chat_template). The "Ollama Modfile" on the
# model card shows a Llama-3 style template, but the model was trained on ChatML: with the Llama-3
# template it answered far too briefly and some JSON-constrained requests failed with HTTP 500.
MODELFILE = f'''FROM /tmp/{GGUF_FILE}
TEMPLATE """{{{{- range .Messages }}}}<|im_start|>{{{{ .Role }}}}
{{{{ .Content }}}}<|im_end|>
{{{{ end }}}}<|im_start|>assistant
"""
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|im_start|>"
PARAMETER temperature 0.2
PARAMETER num_ctx 8192
'''

OLLAMA_ENV = {
    "OLLAMA_HOST": f"0.0.0.0:{OLLAMA_PORT}",
    "OLLAMA_KEEP_ALIVE": "30m",
    "OLLAMA_NUM_PARALLEL": "4",
    "OLLAMA_MODELS": "/root/.ollama/models",
}


def _wait_for_ollama(timeout_s: float = 120) -> None:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{OLLAMA_PORT}/api/version", timeout=2)
            return
        except OSError:
            time.sleep(0.5)
    raise RuntimeError("ollama serve did not start")


def build_model() -> None:
    """Runs once at image build time: download the GGUF and register it in Ollama."""
    from huggingface_hub import hf_hub_download

    hf_hub_download(HF_REPO, GGUF_FILE, local_dir="/tmp")
    with open("/tmp/Modelfile", "w", encoding="utf-8") as f:
        f.write(MODELFILE)
    server = subprocess.Popen(["ollama", "serve"], env={**os.environ, **OLLAMA_ENV})
    try:
        _wait_for_ollama()
        subprocess.run(["ollama", "create", MODEL_NAME, "-f", "/tmp/Modelfile"], check=True)
    finally:
        server.terminate()
        server.wait()
    os.remove(f"/tmp/{GGUF_FILE}")  # Ollama keeps its own copy as a blob


image = (
    modal.Image.debian_slim(python_version="3.12")
    .apt_install("curl", "ca-certificates", "zstd")
    .run_commands("curl -fsSL https://ollama.com/install.sh | sh")
    .pip_install("huggingface_hub[hf_transfer]")
    .env({**OLLAMA_ENV, "HF_HUB_ENABLE_HF_TRANSFER": "1"})
    .run_function(build_model, timeout=3600)
)

app = modal.App("bielik-ollama", image=image)


def _preload_model() -> None:
    """Load the weights into GPU memory right after start, so the first real request is not slower."""
    _wait_for_ollama()
    body = f'{{"model": "{MODEL_NAME}", "keep_alive": "30m"}}'.encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{OLLAMA_PORT}/api/generate", data=body, headers={"Content-Type": "application/json"}
    )
    urllib.request.urlopen(req, timeout=300)


# max_containers=1 and a short scaledown keep the bill small: at most one GPU, off after 2 min idle
@app.function(gpu=GPU, scaledown_window=120, timeout=600, min_containers=MIN_CONTAINERS, max_containers=1)
@modal.concurrent(max_inputs=8)
@modal.web_server(port=OLLAMA_PORT, startup_timeout=300, requires_proxy_auth=True)
def serve():
    subprocess.Popen(["ollama", "serve"], env={**os.environ, **OLLAMA_ENV})
    threading.Thread(target=_preload_model, daemon=True).start()
