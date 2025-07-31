<img width=100% src="https://capsule-render.vercel.app/api?type=waving&height=300&color=gradient&text=🔍%20Scanzy&section=header&reversal=false"/>

Uma ferramenta poderosa para varredura de portas TCP, construída em **Bash** com uma interface gráfica intuitiva em **Python**.

---

##  Sobre o Projeto

Este projeto tem como objetivo combinar a robustez de um scanner TCP em shell script com a praticidade de uma interface visual moderna. Ideal para entusiastas de redes, profissionais de segurança ou qualquer pessoa que precise identificar portas abertas de forma eficiente.

A interface gráfica foi desenvolvida em Python utilizando **PyQt5** (ou **Tkinter**, conforme a implementação), tornando o uso acessível mesmo para quem não domina o terminal.

---

##  Funcionalidades

✅ Escaneamento TCP via `/dev/tcp` (Bash) ou fallback com `netcat (nc)`  
✅ Faixas de portas customizáveis (ex: `1-1024`, `22-25`)  
✅ Timeout ajustável por porta  
✅ Execução paralela com múltiplos jobs (paralelismo configurável)  
✅ Saída no terminal ou em formato JSON  
✅ Detecção básica de serviços (ex: `http`, `ssh`, `ftp`)  
✅ Resolução de DNS automática  
✅ Suporte a interrupções (Ctrl+C) com exibição de resumo parcial  
✅ Interface gráfica simples e funcional para quem prefere clicar em vez de digitar

---

##  Uso via Terminal (Modo CLI)

```bash
chmod +x scanzy.sh

# Exemplos:
./scanzy.sh 192.168.1.1
./scanzy.sh example.com 20-80 --timeout 2 --parallel 20
./scanzy.sh example.com 1-1024 --json
```

##  Uso com Interface Gráfica (Modo GUI)

```bash
# Pré-requisitos:
sudo apt install python3 python3-pip
pip3 install -r requirements.txt

# Executar interface:
./scanzy.sh --gui
```

##  Instalação Rápida

```bash
./setup.sh
```

Esse comando instala todas as dependências e prepara o ambiente automaticamente.

  
##  Sistemas Compatíveis

<div align="center">

| Distribuição             | Compatibilidade                                 |
|--------------------------|-------------------------------------------------|
| `Ubuntu (18.04+)`        | ✅ Totalmente compatível                        |
| `Debian (9+)`            | ✅ Totalmente compatível                        |
| `Kali Linux`             | ✅ Totalmente compatível                        |
| `Arch Linux / Manjaro`   | ✅ Totalmente compatível                        |
| `Fedora / RHEL`          | ✅ Totalmente compatível                        |
| `Alpine Linux`           | ⚠️ Requer instalação extra de bash e coreutils |
| `WSL (Ubuntu/Debian)`    | ✅ Totalmente compatível                        |
| `macOS (bash ≥ 4 + GNU)` | ⚠️ Funciona com ajustes e ferramentas GNU       |

</div>

##  Licença

Este projeto está licenciado sob a MIT License. Consulte o arquivo LICENSE para mais informações.


# 👥 Autores

Desenvolvido por: 404xploit e Miranda-SJ

https://github.com/404xploit

https://github.com/Miranda-SJ
