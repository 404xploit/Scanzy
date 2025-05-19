#!/bin/bash

echo "🔧 Iniciando setup do ambiente..."

# Verifica se está em um sistema baseado em Debian
if ! command -v apt &>/dev/null; then
  echo "❌ Este script foi feito para sistemas Debian-based (Ubuntu, Kali, etc)."
  echo "ℹ️  Para outras distros, instale manualmente: bash, python3, pip3, netcat, bc"
  exit 1
fi

echo "📦 Atualizando pacotes do sistema..."
sudo apt update -y
sudo apt install -y python3 python3-pip bash netcat bc jq build-essential

echo "🐍 Instalando dependências Python do projeto..."
pip3 install -r requirements.txt

echo "✅ Ambiente configurado com sucesso!"
echo ""
echo "ℹ️ Para executar via terminal:"
echo "   ./port_scanner_final.sh <alvo> [faixa_de_portas] [opções]"
echo ""
echo "🖥️ Para executar a interface gráfica:"
echo "   python3 gui/main.py"
