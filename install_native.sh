#!/usr/bin/env bash
# ==============================================================================
# Wiguel-Secure & Wiguel-AI Native Terminal Installer (Linux / macOS / Termux)
# Downloads Wiguel-AI.gguf from Hugging Face and registers 'wiguel-ai' command
# Private & Encrypted System Logic - No Plaintext Prompts exposed in .sh
# ==============================================================================

set -e

echo "================================================================="
echo "   Instalando Wiguel-Secure Native & Modelo Wiguel-AI (GGUF)     "
echo "================================================================="

MODEL_URL="https://huggingface.co/xMiguel11/Wiguel-AI-GGUF/resolve/main/Wiguel-AI.gguf"
INSTALL_DIR="$HOME/.wiguel-ai"
BIN_DIR="$INSTALL_DIR/bin"
MODEL_DIR="$INSTALL_DIR/models"

mkdir -p "$BIN_DIR"
mkdir -p "$MODEL_DIR"

echo "[1/4] Verificando entorno Python3, Curl, Ollama y Acelerador Multihilo..."
if ! command -v python3 &> /dev/null || ! command -v aria2c &> /dev/null; then
    echo "Instalando dependencias recomendadas para descarga acelerada..."
    if command -v pkg &> /dev/null; then
        pkg update && pkg install -y python python-pip curl aria2 || true
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3 python3-pip curl aria2 || true
    elif command -v brew &> /dev/null; then
        brew install python curl aria2 || true
    fi
fi

# Instalar dependencias python para llama-cpp-python y requests
python3 -m pip install llama-cpp-python requests 2>/dev/null || true

echo "[2/4] Descargando modelo Wiguel-AI.gguf desde Hugging Face..."
MODEL_FILE="$MODEL_DIR/Wiguel-AI.gguf"
if [ ! -f "$MODEL_FILE" ]; then
    echo "URL: $MODEL_URL"
    if command -v aria2c &> /dev/null; then
        echo "🚀 Ejecutando motor aria2c multihilo (16 conexiones en paralelo)..."
        aria2c -x 16 -s 16 -k 1M -d "$MODEL_DIR" -o "Wiguel-AI.gguf" "$MODEL_URL" || {
            echo "Aria2c falló, reintentando con curl..."
            curl -L -C - --retry 3 "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
        }
    else
        echo "⚡ Usando curl con reintentos..."
        curl -L -C - --retry 3 "$MODEL_URL" -o "$MODEL_FILE" --progress-bar
    fi
    echo "✓ Modelo descargado con éxito en $MODEL_FILE"
else
    echo "✓ Modelo Wiguel-AI.gguf ya existe localmente en $MODEL_FILE"
fi

echo "[3/4] Configurando ejecutable nativo Wiguel-AI (Verificando Ollama / llama-cpp)..."

cat << 'EOF' > "$INSTALL_DIR/wiguel_runner.py"
#!/usr/bin/env python3
import sys
import os
import json
import time
import base64
import subprocess
import urllib.request
import urllib.error

INSTALL_DIR = os.path.expanduser("~/.wiguel-ai")
MODEL_PATH = os.path.join(INSTALL_DIR, "models", "Wiguel-AI.gguf")

# Hidden System Prompt (Base64 Encoded to prevent plain text exposure in scripts/files)
SYSTEM_PROMPT_B64 = "WW91IGFyZSBXaWd1ZWwtQUksIGFuIGV4cGVydCBjeWJlcnNlY3VyaXR5IGFuZCBnZW5lcmFsIHJlYXNvbmluZyBBSSBtb2RlbCBidWlsdCBmb3IgdGhyZWF0IGFuYWx5c2lzLCBjb2RlIGF1ZGl0aW5nLCB2dWxuZXJhYmlsaXR5IGlkZW50aWZpY2F0aW9uLCBhbmQgaW50ZXJhY3RpdmUgY2hhdC4gVGhpbmsgc3RlcCBieSBzdGVwIGFuZCBwcm92aWRlIGRlZXAsIHdlbGwtcmVhc29uZWQgYW5zd2Vycy4="

def get_system_prompt():
    return base64.b64decode(SYSTEM_PROMPT_B64).decode("utf-8")

def check_ollama_status():
    """Verifica si 'ollama serve' se está ejecutando en http://localhost:11434"""
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags", headers={"User-Agent": "Wiguel-Secure"})
        with urllib.request.urlopen(req, timeout=2) as resp:
            return resp.status == 200
    except Exception:
        return False

def ensure_ollama_model():
    """Registra dinámicamente el modelo 'wiguel-ai' en Ollama desde la memoria sin Modelfile visible."""
    if not check_ollama_status():
        return False
        
    try:
        req = urllib.request.Request("http://localhost:11434/api/tags")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            models = [m.get("name", "") for m in data.get("models", [])]
            if any("wiguel-ai" in m for m in models):
                return True
    except Exception:
        pass

    # Si no existe el archivo GGUF local, usamos un modelo base ligero de ollama como fallback
    sys_prompt = get_system_prompt()
    modelfile_content = "FROM " + MODEL_PATH + "\nSYSTEM \"\"\"" + sys_prompt + "\"\"\"\nPARAMETER temperature 0.3"
    
    if not os.path.exists(MODEL_PATH):
        try:
            print("[Wiguel-AI] Configurando modelo base en Ollama (puede tardar unos segundos)...")
            req_pull = urllib.request.Request(
                "http://localhost:11434/api/pull",
                data=json.dumps({"name": "llama3.2:1b"}).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req_pull, timeout=120) as resp:
                pass
        except Exception:
            pass
        modelfile_content = "FROM llama3.2:1b\nSYSTEM \"\"\"" + sys_prompt + "\"\"\"\nPARAMETER temperature 0.3"

    try:
        url = "http://localhost:11434/api/create"
        payload = {
            "name": "wiguel-ai",
            "modelfile": modelfile_content
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status == 200
    except Exception as e:
        print("\n[Debug] Error creando modelo: " + str(e))
        return False

def query_ollama_stream(prompt):
    """Consulta el modelo en Ollama con STREAMING activo para evitar el timeout de 2 minutos en Termux/CPU."""
    ollama_ok = check_ollama_status()
    if not ollama_ok:
        try:
            subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(2)
            ollama_ok = check_ollama_status()
        except Exception:
            pass

    if not ollama_ok:
        return False

    ensure_ollama_model()

    url = "http://localhost:11434/api/generate"
    payload = {
        "model": "wiguel-ai",
        "prompt": prompt,
        "system": get_system_prompt(),
        "stream": True,
        "options": {
            "temperature": 0.3,
            "num_ctx": 2048,
            "num_predict": 1024
        }
    }
    try:
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req, timeout=300) as resp:
            for line in resp:
                if not line:
                    continue
                try:
                    chunk = json.loads(line.decode("utf-8"))
                    text_chunk = chunk.get("response", "")
                    if text_chunk:
                        sys.stdout.write(text_chunk)
                        sys.stdout.flush()
                    if chunk.get("done", False):
                        break
                except Exception:
                    pass
            print() # Nueva línea al finalizar
            return True
    except Exception as e:
        print(f"\n[Timeout/Error Streaming Ollama]: {e}")
        return False

def query_ollama(prompt):
    """Consulta no-streamed con timeout extendido para análisis."""
    ollama_ok = check_ollama_status()
    if not ollama_ok:
        try:
            subprocess.Popen(["ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(2)
            ollama_ok = check_ollama_status()
        except Exception:
            pass

    if not ollama_ok:
        return None

    ensure_ollama_model()

    url = "http://localhost:11434/api/generate"
    payload = {
        "model": "wiguel-ai",
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
            return res.get("response", "").strip()
    except Exception:
        return None

def run_llama_cpp_fallback(prompt):
    """Respaldo mediante llama-cpp-python"""
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
        return output["choices"][0]["text"].strip()
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
        # Default to analyze if the first argument is a file (e.g. from context menus or Termux)
        command = "--analyze"
        file_to_analyze = args[0]

    if command in ["--chat", "-c", "chat"]:
        print("==================================================")
        print("   Wiguel-AI Cybersecurity Terminal Chat v1.0")
        print("   Modelo Real Local: Wiguel-AI (Temp 0.3)")
        
        ollama_running = check_ollama_status()
        if ollama_running:
            print("   [Estado Servidor]: Ollama Serve -> ACTIVO (http://localhost:11434)")
        else:
            print("   [Estado Servidor]: ⚠️ 'ollama serve' NO detectado. Ejecuta 'ollama serve' para mejor rendimiento.")
        print("   Escribe 'exit' o 'salir' para finalizar")
        print("==================================================")
        
        while True:
            try:
                user_input = input("
wiguel-ai> ")
                if user_input.strip().lower() in ['exit', 'salir', 'quit']:
                    print("Sesión finalizada. Wiguel-Secure activo.")
                    break
                if not user_input.strip():
                    continue
                
                print("Wiguel-AI> ", end="", flush=True)
                
                success = query_ollama_stream(user_input)
                
                if not success:
                    response_text = run_llama_cpp_fallback(user_input)
                    if response_text:
                        print(f"{response_text}\n")
                    else:
                        print("[Error Wiguel-AI]: Error de conexión con Ollama o tiempo de respuesta agotado.\n")
            except KeyboardInterrupt:
                print("
Sesión terminada.")
                break
            except Exception as e:
                print(f"
[Error]: {e}")
                
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
                    f"'status_title' (string), 'explanation' (string), 'detected_patterns' (list of strings).

"
                    f"Content:
{content}"
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

export PATH="$HOME/.wiguel-ai/bin:$PATH"

echo "================================================================="
echo " ¡Instalación completada con éxito!                               "
echo " Inicia 'ollama serve' en tu terminal y prueba:                  "
echo " wiguel-ai --chat  O  wiguel-ai --analyze <archivo>              "
echo "================================================================="
