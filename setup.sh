#!/bin/bash

echo "  ####     ####      ##     ##  ##   ######   ##  ##             ####    ######   ######   ##  ##   #####"
echo " ##  ##   ##  ##    ####    ### ##       ##   ##  ##            ##  ##   ##         ##     ##  ##   ##  ##"
echo " ##       ##       ##  ##   ######      ##    ##  ##            ##       ##         ##     ##  ##   ##  ##"
echo "  ####    ##       ######   ######     ##      ####              ####    ####       ##     ##  ##   #####"
echo "     ##   ##       ##  ##   ## ###    ##        ##                  ##   ##         ##     ##  ##   ##"
echo " ##  ##   ##  ##   ##  ##   ##  ##   ##         ##              ##  ##   ##         ##     ##  ##   ##"
echo "  ####     ####    ##  ##   ##  ##   ######     ##               ####    ######     ##      ####    ##"

echo "Scanzy - Scanner de portas"
echo "🔧 Iniciando setup do ambiente para o Scanzy..."

# Verifica se está em um sistema baseado em Debian
if ! command -v apt &>/dev/null; then
  echo "❌ Este script é compatível apenas com distribuições baseadas em Debian (Ubuntu, Kali, etc)."
  echo "ℹ️  Para outras distros, instale manualmente: bash, python3, pip3, netcat, bc"
  exit 1
fi

echo "📦 Atualizando pacotes do sistema..."
sudo apt update -y

echo "📦 Instalando dependências do sistema..."
sudo apt install -y python3 python3-pip python3-venv python3-dev build-essential \
                    bash netcat bc jq libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
                    libsdl2-ttf-dev libmtdev-dev libgl1-mesa-dev libgles2-mesa-dev \
                    libgstreamer1.0 libgstreamer1.0-dev xclip xsel ffmpeg

echo "🐍 Criando e ativando ambiente virtual..."
python3 -m venv .venv
source .venv/bin/activate

echo "🐍 Instalando dependências Python do projeto..."
pip install --upgrade pip
pip install -r requirements.txt

echo ""
echo "✅ Ambiente configurado com sucesso!"
echo ""
echo "📂 Para executar via terminal (modo CLI):"
echo "   ./scanzy.sh <alvo> [faixa_de_portas] [opções]"
echo ""
echo "🖥️  Para executar a interface gráfica (modo GUI):"
echo "   ./scanzy.sh --gui"
