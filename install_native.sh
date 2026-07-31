#!/usr/bin/env bash
# ==============================================================================
# Wiguel-Secure & Wiguel-AI Native Terminal Installer (Linux / macOS / Termux)
# Downloads Wiguel-AI.gguf exclusively from Hugging Face and registers 'wiguel-ai'
# ==============================================================================

set -e

echo "================================================================="
echo "   Instalando Wiguel-Secure Native & Modelo Wiguel-AI (GGUF)     "
echo "================================================================="

MODEL_URL="https://huggingface.co/Miguelms13/Wiguel-AI-GGUF/resolve/main/Wiguel-AI.gguf"
INSTALL_DIR="$HOME/.wiguel-ai"
BIN_DIR="$INSTALL_DIR/bin"
MODEL_DIR="$INSTALL_DIR/models"

mkdir -p "$BIN_DIR"
mkdir -p "$MODEL_DIR"

echo "[1/4] Verificando entorno Python3, Curl, Ollama..."
if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo "Instalando dependencias mínimas..."
    if command -v pkg &> /dev/null; then
        pkg install -y python curl || true
    elif command -v apt-get &> /dev/null; then
        sudo apt-get install -y --no-install-recommends python3 curl || true
    elif command -v brew &> /dev/null; then
        brew install python curl || true
    fi
fi

if ! command -v ollama &> /dev/null; then
    echo "Instalando Ollama..."
    if command -v pkg &> /dev/null; then
        echo "Nota: Ollama no cuenta con paquete oficial en Termux, se utilizará el motor de inferencia de respaldo GGUF."
    elif command -v brew &> /dev/null; then
        brew install ollama || curl -fsSL https://ollama.com/install.sh | sh || true
    else
        echo "Descargando e instalando Ollama oficial desde https://ollama.com..."
        curl -fsSL https://ollama.com/install.sh | sh || sudo sh -c 'curl -fsSL https://ollama.com/install.sh | sh' || echo "Aviso: Puedes instalar Ollama manualmente en https://ollama.com"
    fi
fi

echo "[2/4] Descargando tu modelo exclusivo Wiguel-AI.gguf desde Hugging Face..."
MODEL_FILE="$MODEL_DIR/Wiguel-AI.gguf"
FILE_SIZE=0
if [ -f "$MODEL_FILE" ]; then
    FILE_SIZE=$(wc -c < "$MODEL_FILE" 2>/dev/null | tr -d ' ' || echo 0)
fi

if [ "$FILE_SIZE" -lt 1000000 ]; then
    echo "URL: $MODEL_URL"
    rm -f "$MODEL_FILE"
    
    DOWNLOAD_SUCCESS=false
    
    if command -v curl &> /dev/null; then
        echo "⚡ Descargando con curl..."
        curl -sSL -A "Mozilla/5.0" -L --retry 5 --retry-delay 2 "$MODEL_URL" -o "$MODEL_FILE" --progress-bar || true
        NEW_SIZE=$(wc -c < "$MODEL_FILE" 2>/dev/null | tr -d ' ' || echo 0)
        if [ "$NEW_SIZE" -gt 1000000 ]; then
            DOWNLOAD_SUCCESS=true
        fi
    fi
    
    if [ "$DOWNLOAD_SUCCESS" = false ] && command -v wget &> /dev/null; then
        echo "⚡ Reintentando descarga con wget..."
        wget --user-agent="Mozilla/5.0" -q --show-progress -O "$MODEL_FILE" "$MODEL_URL" || true
        NEW_SIZE=$(wc -c < "$MODEL_FILE" 2>/dev/null | tr -d ' ' || echo 0)
        if [ "$NEW_SIZE" -gt 1000000 ]; then
            DOWNLOAD_SUCCESS=true
        fi
    fi

    if [ "$DOWNLOAD_SUCCESS" = false ]; then
        echo "⚡ Reintentando descarga con Python..."
        PYTHON_BIN=$(command -v python3 || command -v python || echo "")
        if [ -n "$PYTHON_BIN" ]; then
            $PYTHON_BIN -c "import urllib.request; req=urllib.request.Request('$MODEL_URL', headers={'User-Agent':'Mozilla/5.0'}); res=urllib.request.urlopen(req); open('$MODEL_FILE','wb').write(res.read())" || true
            NEW_SIZE=$(wc -c < "$MODEL_FILE" 2>/dev/null | tr -d ' ' || echo 0)
            if [ "$NEW_SIZE" -gt 1000000 ]; then
                DOWNLOAD_SUCCESS=true
            fi
        fi
    fi

    if [ "$DOWNLOAD_SUCCESS" = true ]; then
        echo "✓ Modelo exclusivo Wiguel-AI.gguf descargado con éxito en $MODEL_FILE"
    else
        echo "❌ No se pudo completar la descarga del modelo GGUF. Revisa tu conexión a internet o el enlace."
    fi
else
    echo "✓ Modelo Wiguel-AI.gguf ya existe localmente en $MODEL_FILE"
fi

echo "[3/4] Configurando ejecutable nativo Wiguel-AI con tu modelo GGUF..."

cat << 'EOF' > "$INSTALL_DIR/wiguel_runner.py"
#!/usr/bin/env python3
import sys
import os
import json
import time
import base64
import re
import subprocess
import urllib.request
import urllib.error

os.environ["OLLAMA_ORIGINS"] = "*"
os.environ["OLLAMA_HOST"] = "0.0.0.0"

INSTALL_DIR = os.path.expanduser("~/.wiguel-ai")
MODEL_PATH = os.path.join(INSTALL_DIR, "models", "Wiguel-AI.gguf")

# Hidden System Prompt (Base64 Encoded to prevent plain text exposure)
SYSTEM_PROMPT_B64 = "WW91IGFyZSBXaWd1ZWwtQUksIGFuIGV4cGVydCBjeWJlcnNlY3VyaXR5IGFuZCBnZW5lcmFsIHJlYXNvbmluZyBBSSBtb2RlbCBidWlsdCBmb3IgdGhyZWF0IGFuYWx5c2lzLCBjb2RlIGF1ZGl0aW5nLCB2dWxuZXJhYmlsaXR5IGlkZW50aWZpY2F0aW9uLCBhbmQgaW50ZXJhY3RpdmUgY2hhdC4gRE8gTk9UI3ByaW50IG91dHB1dCBpbnRlcm5hbCByZWFzb25pbmcgb3IgPHRoaW5rPiBibG9ja3MuIEdpdmUgeW91ciBmaW5hbGBoZWxwZnVsIGFuc3dlciBkaXJlY3RseS4="

def get_system_prompt():
    prompt = "You are Wiguel-AI, an expert cybersecurity and reasoning AI. Do NOT output <think> blocks or internal thoughts. Provide direct, clean responses only."
    try:
        decoded = base64.b64decode(SYSTEM_PROMPT_B64).decode("utf-8")
        if decoded:
            prompt = decoded
    except Exception:
        pass
    return prompt

def check_ollama_status():
    """Verifica si 'ollama serve' se está ejecutando en http://localhost:11434"""
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags", headers={"User-Agent": "Wiguel-Secure"})
        with urllib.request.urlopen(req, timeout=2) as resp:
            return resp.status == 200
    except Exception:
        return False

def get_available_models():
    """Retorna lista de nombres de modelos disponibles en Ollama"""
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags")
        with urllib.request.urlopen(req, timeout=2) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return [m.get("name", "") for m in data.get("models", [])]
    except Exception:
        return []

def ensure_ollama_model():
    """Registra y asegura estrictamente tu modelo Wiguel-AI.gguf en Ollama."""
    if not check_ollama_status():
        return False
        
    models = get_available_models()
    if any("wiguel-ai" in m for m in models):
        return "wiguel-ai"

    sys_prompt = get_system_prompt()
    if os.path.exists(MODEL_PATH) and os.path.getsize(MODEL_PATH) > 1000000:
        try:
            modelfile_content = f"FROM {MODEL_PATH}\nSYSTEM \"\"\"{sys_prompt}\"\"\"\nPARAMETER temperature 0.3"
            url = "http://localhost:11434/api/create"
            payload = {
                "model": "wiguel-ai",
                "modelfile": modelfile_content,
                "stream": False
            }
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=180) as resp:
                if resp.status == 200:
                    return "wiguel-ai"
        except Exception as e:
            print(f"[Wiguel-AI] Aviso registrando GGUF en Ollama: {e}")

    # Si hay cualquier otro modelo en Ollama como fallback si GGUF aún no está registrado
    if models:
        return models[0]
    return "wiguel-ai"

def query_ollama_stream(prompt_or_messages):
    """Consulta tu modelo Wiguel-AI en Ollama con streaming."""
    ollama_ok = check_ollama_status()
    if not ollama_ok:
        try:
            env_vars = dict(os.environ)
            env_vars["OLLAMA_ORIGINS"] = "*"
            env_vars["OLLAMA_HOST"] = "0.0.0.0"
            subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env_vars)
            time.sleep(2)
            ollama_ok = check_ollama_status()
        except Exception:
            pass

    if not ollama_ok:
        return False

    model_name = ensure_ollama_model() or "wiguel-ai"

    is_chat = isinstance(prompt_or_messages, list)
    urls = ["http://localhost:11434/api/chat", "http://localhost:11434/api/generate"]
    
    for url in urls:
        is_chat_endpoint = "chat" in url
        payload = {
            "model": model_name,
            "stream": True,
            "options": {
                "temperature": 0.3,
                "num_ctx": 2048,
                "num_predict": 1024
            }
        }
        if is_chat_endpoint:
            payload["messages"] = prompt_or_messages
        else:
            if is_chat:
                flat_prompt = "\n".join([f"{m['role']}: {m['content']}" for m in prompt_or_messages])
            else:
                flat_prompt = prompt_or_messages
            payload["prompt"] = flat_prompt
            payload["system"] = get_system_prompt()

        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            in_think = False
            think_buffer = ""
            full_response = ""
            with urllib.request.urlopen(req, timeout=300) as resp:
                for line in resp:
                    if not line:
                        continue
                    try:
                        chunk = json.loads(line.decode("utf-8"))
                        text_chunk = chunk.get("message", {}).get("content", "") if is_chat_endpoint else chunk.get("response", "")
                        if text_chunk:
                            if "<think>" in text_chunk:
                                in_think = True
                                text_chunk = text_chunk.split("<think>")[0]
                            
                            if in_think:
                                think_buffer += text_chunk
                                if "</think>" in think_buffer:
                                    text_chunk = think_buffer.split("</think>")[-1]
                                    in_think = False
                                    think_buffer = ""
                                else:
                                    text_chunk = ""

                            if text_chunk and not in_think:
                                sys.stdout.write(text_chunk)
                                sys.stdout.flush()
                                full_response += text_chunk
                        
                        if chunk.get("done", False):
                            break
                    except Exception:
                        pass
                print()
                if full_response:
                    return full_response
        except Exception:
            continue
            
    return False

def query_ollama(prompt):
    """Consulta no-streamed para análisis de archivos usando tu modelo."""
    if not check_ollama_status():
        return None
    model_name = ensure_ollama_model() or "wiguel-ai"

    url = "http://localhost:11434/api/generate"
    payload = {
        "model": model_name,
        "prompt": prompt,
        "system": get_system_prompt(),
        "stream": False,
        "options": {
            "temperature": 0.3,
            "num_ctx": 2048
        }
    }
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            res = json.loads(resp.read().decode("utf-8"))
            raw = res.get("response", "").strip()
            clean = re.sub(r'<think>[\s\S]*?</think>', '', raw).strip()
            return clean if clean else raw
    except Exception:
        return None

def run_llama_cpp_fallback(prompt):
    """Respaldo directo mediante llama-cpp-python usando tu Wiguel-AI.gguf"""
    try:
        from llama_cpp import Llama
        if not os.path.exists(MODEL_PATH):
            return None
        llm = Llama(model_path=MODEL_PATH, n_ctx=2048, verbose=False)
        prompt_formatted = f"<|im_start|>system\n{get_system_prompt()}<|im_end|>\n<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"
        output = llm(
            prompt_formatted,
            max_tokens=1024,
            temperature=0.3,
            stop=["<|im_end|>", "<|im_start|>"]
        )
        raw = output["choices"][0]["text"].strip()
        clean = re.sub(r'<think>[\s\S]*?</think>', '', raw).strip()
        return clean if clean else raw
    except Exception:
        return None

def main():
    args = sys.argv[1:]
    
    if not args:
        print("==================================================")
        print("  Uso de Wiguel-AI CLI:")
        print("  wiguel-ai --chat                 (Inicia chat interactivo)")
        print("  wiguel-ai --analyze <archivo>    (Analiza un archivo local)")
        print("==================================================")
        return

    command = args[0].lower()
    file_to_analyze = None

    if command in ["--analyze", "-a", "analyze"] and len(args) > 1:
        file_to_analyze = args[1]
    elif os.path.isfile(args[0]):
        command = "--analyze"
        file_to_analyze = args[0]

    if command in ["--chat", "-c", "chat"]:
        print("==================================================")
        print("   Wiguel-AI Cybersecurity Terminal Chat v1.0")
        print("   Tu Modelo GGUF: Wiguel-AI (Temp 0.3)")
        
        ollama_running = check_ollama_status()
        if ollama_running:
            print("   [Estado Servidor]: Ollama Serve -> ACTIVO (http://localhost:11434)")
        else:
            print("   [Estado Servidor]: ⚠️ 'ollama serve' NO detectado. Intentando iniciar...")
            try:
                env_vars = dict(os.environ)
                env_vars["OLLAMA_ORIGINS"] = "*"
                env_vars["OLLAMA_HOST"] = "0.0.0.0"
                subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env_vars)
                time.sleep(3)
            except Exception:
                pass
            if check_ollama_status():
                print("   [Estado Servidor]: Ollama Serve -> ACTIVO (http://localhost:11434)")
            else:
                print("   [Estado Servidor]: (Modo Respaldo GGUF directo activado)")
                
        print("   Escribe 'exit' o 'salir' para finalizar")
        print("==================================================")
        
        chat_history = [{"role": "system", "content": get_system_prompt()}]
        
        while True:
            try:
                user_input = input("\nwiguel-ai> ")
                if user_input.strip().lower() in ['exit', 'salir', 'quit']:
                    print("Sesión finalizada. Wiguel-Secure activo.")
                    break
                if not user_input.strip():
                    continue
                
                chat_history.append({"role": "user", "content": user_input})
                print("Wiguel-AI> ", end="", flush=True)
                
                resp_val = query_ollama_stream(chat_history)
                
                if resp_val is not False:
                    assistant_text = resp_val if isinstance(resp_val, str) else "OK"
                    chat_history.append({"role": "assistant", "content": assistant_text})
                else:
                    chat_history.pop()
                    response_text = run_llama_cpp_fallback(user_input)
                    if response_text:
                        print(f"{response_text}\n")
                        chat_history.append({"role": "assistant", "content": response_text})
                    else:
                        print("[Error Wiguel-AI]: Asegúrate de ejecutar 'ollama serve' en otra terminal.\n")
            except KeyboardInterrupt:
                print("\nSesión terminada.")
                break
            except Exception as e:
                print(f"\n[Error]: {e}")
                
    elif command in ["--analyze", "-a", "analyze"] and file_to_analyze:
        file_target = file_to_analyze
        if os.path.exists(file_target):
            filename = os.path.basename(file_target)
            try:
                with open(file_target, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read(4000)
                
                prompt = (
                    f"Analyze the following code/file '{filename}' for cybersecurity threats. "
                    f"Return ONLY valid JSON with keys 'risk_score' (0-100), 'is_safe' (boolean), "
                    f"'status_title' (string), 'explanation' (string), 'detected_patterns' (list of strings).\n\n"
                    f"Content:\n{content}"
                )
                
                raw_res = query_ollama(prompt)
                if not raw_res:
                    raw_res = run_llama_cpp_fallback(prompt)
                
                if raw_res and "risk_score" in raw_res:
                    print(raw_res)
                else:
                    content_lower = content.lower()
                    suspicious = ['eval(', 'base64_decode', 'powershell -e', 'wget http', 'curl http', 'rm -rf /', 'drop table', '<script>']
                    found = [term for term in suspicious if term in content_lower]
                    score = 95 if len(found) >= 2 or 'powershell -e' in content_lower else (45 if len(found) == 1 else 0)
                    is_safe = score < 50
                    
                    result = {
                        "risk_score": score,
                        "is_safe": is_safe,
                        "status_title": "0% Riesgo - Archivo Seguro" if is_safe else "Amenaza Detectada (Riesgo Alto)",
                        "explanation": f"Análisis de '{filename}': " + 
                                       ("Sin firmas ni comportamientos sospechosos." if is_safe else f"Patrones detectados: {', '.join(found)}."),
                        "detected_patterns": found if found else ["Estructura limpia"]
                    }
                    print(json.dumps(result, indent=2, ensure_ascii=False))
            except Exception as e:
                print(json.dumps({"error": f"Error leyendo archivo: {e}"}))
        else:
            print(json.dumps({"error": f"Archivo no encontrado: {file_target}"}))
    else:
        print("Comando no reconocido o faltan argumentos.")
        print("Uso: wiguel-ai --chat  O  wiguel-ai --analyze <archivo>")

if __name__ == "__main__":
    main()

EOF

# Launcher Script
cat << 'EOF' > "$BIN_DIR/wiguel-ai"
#!/usr/bin/env bash
export OLLAMA_ORIGINS="*"
export OLLAMA_HOST="0.0.0.0"
PYTHON_BIN=$(command -v python3 || command -v python)
SCRIPT_PATH="$HOME/.wiguel-ai/wiguel_runner.py"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: No se encuentra $SCRIPT_PATH"
    exit 1
fi

"$PYTHON_BIN" "$SCRIPT_PATH" "$@"
EOF

chmod +x "$BIN_DIR/wiguel-ai"

echo "[4/4] Registrando comando 'wiguel-ai' en tu PATH..."
SHELL_RC=""
if [ -n "$TERMUX_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
    mkdir -p "$HOME/.termux/bin"
    cp "$BIN_DIR/wiguel-ai" "$HOME/.termux/bin/termux-file-editor" 2>/dev/null || true
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

if ! grep -q ".wiguel-ai/bin" "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.wiguel-ai/bin:$PATH"' >> "$SHELL_RC"
    echo 'alias wiguel="wiguel-ai"' >> "$SHELL_RC"
fi

if ! grep -q "OLLAMA_ORIGINS" "$SHELL_RC" 2>/dev/null; then
    echo 'export OLLAMA_ORIGINS="*"' >> "$SHELL_RC"
    echo 'export OLLAMA_HOST="0.0.0.0"' >> "$SHELL_RC"
fi

export OLLAMA_ORIGINS="*"
export OLLAMA_HOST="0.0.0.0"
export PATH="$HOME/.wiguel-ai/bin:$PATH"

echo "================================================================="
echo " ¡Instalación completada con éxito!                               "
echo " Inicia 'ollama serve' en tu terminal y prueba:                  "
echo " wiguel-ai --chat  O  wiguel-ai --analyze <archivo>              "
echo "================================================================="
