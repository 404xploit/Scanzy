#!/bin/bash

echo "🔧 Iniciando setup do ambiente..."

# Verifica se está em um sistema baseado em Debian
if ! command -v apt &>/dev/null; then
  echo "❌ Este script foi feito para distribuições baseadas em Debian (Ubuntu, Kali, etc)."
  echo "ℹ️  Para outras distros, instale manualmente: python3, pip3, netcat, bc, jq, build-essential"
  exit 1
fi

# Atualiza o cache de pacotes
echo "📦 Atualizando pacotes do sistema..."
sudo apt update -y

# (Opcional) Remoção de versões antigas do Python — cuidado, pode quebrar o sistema em algumas distros
read -p "⚠️ Deseja remover a instalação atual do Python3? (isso pode afetar o sistema) [s/N]: " resposta
if [[ "$resposta" =~ ^[sS]$ ]]; then
  echo "🐍 Removendo instalação atual do Python..."
  sudo apt remove --purge -y python3 python3-pip python3-dev
  sudo apt autoremove -y
fi

# Instala dependências do sistema
echo "📦 Instalando Python e dependências do sistema..."
sudo apt install -y python3 python3-pip python3-dev bash netcat bc jq build-essential

# Instala dependências Python do projeto
if [ -f "requirements.txt" ]; then
  echo "🐍 Instalando dependências Python do projeto..."
  pip3 install -r requirements.txt
else
  echo "⚠️ Arquivo requirements.txt não encontrado. Pulando etapa de pip."
fi

echo ""
echo "✅ Ambiente configurado com sucesso!"
echo ""
echo "📂 Para executar via terminal (modo CLI):"
echo "   ./port_scanner_final.sh <alvo> [faixa_de_portas] [opções]"
echo ""
echo "🖥️  Para executar a interface gráfica:"
echo "   python3 gui/main.py"
