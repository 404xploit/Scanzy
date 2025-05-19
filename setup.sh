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

echo "🐍 Removendo instalação atual do Python..."
sudo apt remove --purge -y python3 python3-pip python3-minimal

echo "🐍 Instalando Python e dependências do sistema..."
sudo apt install -y python3 python3-pip python3-dev python3-venv bash netcat bc jq build-essential

echo "🐍 Criando e ativando ambiente virtual..."
python3 -m venv .venv
source .venv/bin/activate

echo "🐍 Instalando dependências Python do projeto..."
pip3 install --upgrade pip
pip3 install -r requirements.txt

echo "✅ Ambiente configurado com sucesso!"
echo ""
echo "ℹ️ Para executar via terminal:"
echo "   ./port_scanner_final.sh <alvo> [faixa_de_portas] [opções]"
echo ""
echo "🖥️ Para executar a interface gráfica:"
echo "   source .venv/bin/activate && python3 gui/main.py"