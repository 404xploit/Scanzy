#!/bin/bash

# scanzy.sh - Scanner de Portas TCP Avançado
# Autor: 404xploit
# Data: 15 de Maio de 2025
# Versão: 1.0
#
# Descrição:
# Este script realiza varredura de portas TCP em um host especificado.
# Suporta varredura paralela, timeout configurável, saída em formato JSON,
# detecção básica de serviços, resolução de DNS, fallback para netcat (nc)
# se /dev/tcp não estiver disponível, e tratamento de interrupção (Ctrl+C).
#
# Funcionalidades Principais:
# 1. Varredura TCP usando /dev/tcp (padrão) ou netcat (fallback ou forçado).
# 2. Faixa de portas configurável (padrão: 1-1024).
# 3. Timeout configurável para cada tentativa de conexão (padrão: 1s).
# 4. Varredura paralela com número de jobs configurável (padrão: 10).
# 5. Saída em formato texto (padrão) ou JSON (opção --json).
# 6. Detecção básica de nomes de serviços para portas comuns.
# 7. Resolução de hostname para endereço IP.
# 8. Tratamento de interrupção (Ctrl+C) com resumo parcial.
# 9. Validação robusta de parâmetros de entrada.

# --- Configurações Padrão ---
DEFAULT_PORT_RANGE="1-1024"       # Faixa de portas padrão se nenhuma for especificada.
DEFAULT_TIMEOUT_SECONDS=1       # Timeout padrão por porta em segundos.
DEFAULT_PARALLEL_JOBS=10        # Número padrão de jobs paralelos.
OUTPUT_JSON=false               # Flag para controlar a saída JSON. Inicialmente falso.
FORCE_USE_NETCAT=false          # Flag para forçar o uso de netcat. Inicialmente falso.

# --- Variáveis Globais para Tratamento de Sinais e Resumo ---
# Estas variáveis são usadas para gerenciar o estado durante a varredura
# e para fornecer um resumo em caso de interrupção.
declare -a CHILD_PIDS=()            # Array para armazenar PIDs dos jobs de varredura em background.
TMP_OPEN_PORTS_FILE=""            # Caminho para o arquivo temporário que armazena portas abertas encontradas.
SCAN_START_TIME_NS=0              # Timestamp (nanossegundos) do início da varredura, para cálculo de duração.
TOTAL_PORTS_TO_SCAN_FOR_SUMMARY=0 # Número total de portas que o script tentará escanear.

# --- Funções Auxiliares ---

# Função: show_help
# Descrição: Exibe a mensagem de ajuda do script, detalhando o uso, argumentos e opções.
show_help() {
    echo "Uso: $0 <host> [faixa_de_portas] [opções]"
    echo ""
    echo "Argumentos Posicionais:"
    echo "  <host>                Endereço IP ou hostname do alvo (obrigatório)."
    echo "  [faixa_de_portas]     Faixa de portas a ser escaneada (ex: 1-1024, 80, 22-25)."
    echo "                        Padrão: $DEFAULT_PORT_RANGE"
    echo ""
    echo "Opções:"
    echo "  --timeout <segundos>  Timeout para cada tentativa de conexão em segundos."
    echo "                        Padrão: $DEFAULT_TIMEOUT_SECONDS segundo(s)."
    echo "  --parallel <jobs>     Número de varreduras de porta paralelas."
    echo "                        Padrão: $DEFAULT_PARALLEL_JOBS jobs."
    echo "  --json                Formatar a saída como JSON."
    echo "  --force-netcat        Forçar o uso de netcat (nc) para varredura."
    echo "  -h, --help            Exibir esta mensagem de ajuda."
    echo ""
    echo "Exemplos:"
    echo "  $0 example.com"
    echo "  $0 192.168.1.1 1-100 --json"
    echo "  $0 scanme.nmap.org 20-25 --timeout 2 --parallel 5 --force-netcat"
    echo ""
    echo "Nota: Pressione Ctrl+C para interromper a varredura e exibir um resumo parcial."
}

# Função: handle_interrupt
# Descrição: Trata o sinal de interrupção (SIGINT/Ctrl+C, SIGTERM).
#            Encerra os jobs de varredura filhos, exibe um resumo parcial
#            das portas encontradas e do tempo decorrido, e limpa o arquivo temporário.
handle_interrupt() {
    echo "" # Adiciona uma nova linha para clareza na saída do terminal.
    echo "[!] Varredura interrompida pelo usuário (Ctrl+C)." >&2

    # Encerra todos os processos filhos (jobs de varredura) que ainda possam estar rodando.
    if [ ${#CHILD_PIDS[@]} -gt 0 ]; then
        for pid in "${CHILD_PIDS[@]}"; do
            kill "$pid" 2>/dev/null # Suprime erros se o PID já terminou ou não existe.
        done
    fi
    # Espera um pouco para que os processos filhos realmente terminem e o shell limpe suas entradas.
    # Isso ajuda a evitar mensagens de "Terminated" na saída do terminal após o script sair.
    wait &>/dev/null

    # Calcula o tempo decorrido desde o início da varredura.
    local current_time_ns=$(date +%s%N)
    local duration_ns=$((current_time_ns - SCAN_START_TIME_NS))
    local duration_s_formatted=$(printf "%.1f" $(echo "scale=1; $duration_ns / 1000000000" | bc -l))

    # Lê as portas abertas encontradas até o momento da interrupção do arquivo temporário.
    declare -a open_ports_summary
    if [ -f "$TMP_OPEN_PORTS_FILE" ] && [ -s "$TMP_OPEN_PORTS_FILE" ]; then
        readarray -t open_ports_summary < <(sort -n "$TMP_OPEN_PORTS_FILE" | uniq)
    fi

    # Exibe o resumo parcial.
    echo "[*] Portas abertas encontradas até o momento: ${open_ports_summary[*]:-(Nenhuma)}" >&2
    echo "[*] Tempo decorrido: ${duration_s_formatted}s" >&2
    
    # Limpa o arquivo temporário de portas abertas.
    if [ -n "$TMP_OPEN_PORTS_FILE" ] && [ -f "$TMP_OPEN_PORTS_FILE" ]; then
        rm -f "$TMP_OPEN_PORTS_FILE"
    fi
    # Sai com o código 130, que é o padrão para scripts encerrados por Ctrl+C.
    exit 130 
}

# Função: validate_positive_integer
# Descrição: Valida se um valor fornecido é um inteiro positivo.
# Parâmetros:
#   $1: O valor a ser validado.
#   $2: O nome do parâmetro (para mensagens de erro, ex: "Timeout").
validate_positive_integer() {
    local value="$1"
    local name="$2"
    local error_message="[!] Erro: $name deve ser um inteiro positivo (recebido: $value)."
    # Verifica se o valor contém apenas dígitos e é maior que zero.
    if ! [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]]; then
        if $OUTPUT_JSON; then
            # No modo JSON, erros devem ser mínimos ou formatados em JSON. Aqui, apenas sai.
            # Uma implementação mais completa poderia gerar um JSON de erro.
            exit 1 # Falha silenciosa para JSON, ou poderia ser um JSON de erro.
        else
            echo "$error_message" >&2
        fi
        exit 1
    fi
}

# Função: get_service_name
# Descrição: Retorna o nome de serviço comum para uma porta TCP conhecida.
# Parâmetros:
#   $1: O número da porta.
# Retorna: O nome do serviço (ex: "http") ou uma string vazia se não for conhecido.
get_service_name() {
    local port="$1"
    case "$port" in
        21) echo "ftp" ;; 
        22) echo "ssh" ;; 
        23) echo "telnet" ;; 
        25) echo "smtp" ;; 
        53) echo "dns" ;; 
        80) echo "http" ;; 
        110) echo "pop3" ;; 
        143) echo "imap" ;; 
        443) echo "https" ;; 
        3306) echo "mysql" ;; 
        3389) echo "rdp" ;; 
        5432) echo "postgresql" ;; 
        5900) echo "vnc" ;; 
        8080) echo "http-proxy" ;; 
        *) echo "" ;; # Retorna string vazia se não for um serviço comum conhecido
    esac
}
export -f get_service_name # Exporta a função para que esteja disponível nos subshells dos jobs paralelos.

# Função: parse_ports
# Descrição: Analisa a string de faixa de portas fornecida e gera uma sequência de portas individuais.
#            Suporta formatos como "80" (porta única) ou "22-25" (faixa).
# Parâmetros:
#   $1: A string da faixa de portas (ex: "1-1024", "80").
# Retorna: Uma lista de portas, uma por linha, para stdout.
parse_ports() {
    local port_range_str="$1"
    local error_prefix="[!] Erro:"
    if $OUTPUT_JSON; then error_prefix=""; fi # Suprime prefixo de erro para saída JSON.

    if [[ "$port_range_str" == *","* ]]; then # Formato de lista (ex: 22,80,443) não é suportado nesta versão.
        if ! $OUTPUT_JSON; then echo "${error_prefix}Formato de lista de portas (ex: 22,80,443) ainda não é suportado." >&2; fi
        exit 1
    elif [[ "$port_range_str" == *"-"* ]]; then # Formato de faixa (ex: 1-1024).
        local start_port end_port
        start_port=$(echo "$port_range_str" | cut -d'-' -f1)
        end_port=$(echo "$port_range_str" | cut -d'-' -f2)
        # Valida se a faixa de portas é numericamente válida e dentro dos limites (1-65535).
        if ! [[ "$start_port" =~ ^[0-9]+$ && "$end_port" =~ ^[0-9]+$ && \
                "$start_port" -ge 1 && "$start_port" -le 65535 && \
                "$end_port" -ge 1 && "$end_port" -le 65535 && \
                "$start_port" -le "$end_port" ]]; then
            if ! $OUTPUT_JSON; then echo "${error_prefix}Faixa de portas inválida: $port_range_str. Use INICIO-FIM (1-65535)." >&2; fi
            exit 1
        fi
        seq "$start_port" "$end_port" # Gera a sequência de portas.
    elif [[ "$port_range_str" =~ ^[0-9]+$ ]]; then # Formato de porta única (ex: 80).
        # Valida se a porta única está dentro dos limites (1-65535).
        if ! [[ "$port_range_str" -ge 1 && "$port_range_str" -le 65535 ]]; then
            if ! $OUTPUT_JSON; then echo "${error_prefix}Número de porta inválido: $port_range_str. Deve estar entre 1-65535." >&2; fi
            exit 1
        fi
        echo "$port_range_str"
    else # Formato desconhecido.
        if ! $OUTPUT_JSON; then echo "${error_prefix}Formato de faixa de portas desconhecido: $port_range_str. Use N ou N-M." >&2; fi
        exit 1
    fi
}

# Função: scan_port_job
# Descrição: Realiza a tentativa de conexão a uma porta específica de um host.
#            Esta função é projetada para ser executada em background como um job paralelo.
# Parâmetros:
#   $1 (host): O endereço IP ou hostname do alvo.
#   $2 (port): O número da porta a ser escaneada.
#   $3 (connect_timeout): O timeout em segundos para a tentativa de conexão.
#   $4 (tmp_file): O caminho para o arquivo temporário onde portas abertas são registradas.
#   $5 (output_json_flag): Booleano (true/false) indicando se a saída JSON está ativa.
scan_port_job() {
    local host="$1"
    local port="$2"
    local connect_timeout="$3"
    local tmp_file="$4"
    local output_json_flag="$5"
    # ACTUAL_SCAN_METHOD é uma variável global (exportada) que define o método de varredura.
    
    local port_is_open=false
    if [ "$ACTUAL_SCAN_METHOD" == "devtcp" ]; then
        # Tenta conectar usando /dev/tcp. O subshell (bash -c) garante que o descritor de arquivo 3 é local.
        # Redireciona stderr para /dev/null para suprimir mensagens de erro de conexão.
        if timeout "${connect_timeout}s" bash -c "exec 3<> /dev/tcp/$host/$port" 2>/dev/null; then
            port_is_open=true
            # Fecha explicitamente os descritores de arquivo abertos pelo /dev/tcp.
            exec 3<&- # Fecha o lado de leitura do descritor 3.
            exec 3>&- # Fecha o lado de escrita do descritor 3.
        fi
    elif [ "$ACTUAL_SCAN_METHOD" == "netcat" ]; then
        # Tenta conectar usando netcat (nc) com modo -z (zero I/O, apenas verifica se a porta está escutando)
        # e timeout -w (em segundos).
        if nc -z -w "$connect_timeout" "$host" "$port" 2>/dev/null; then
            port_is_open=true
        fi
    fi

    if $port_is_open; then
        # Se a porta estiver aberta:
        # No modo texto (não JSON), imprime imediatamente a informação da porta aberta.
        if ! $output_json_flag; then 
            service_name=$(get_service_name "$port")
            if [ -n "$service_name" ]; then
                # Usar printf para garantir que a saída seja atômica e evitar problemas de intercalação com jobs paralelos.
                printf "[+] Porta %s/tcp aberta (%s)\n" "$port" "$service_name"
            else
                printf "[+] Porta %s/tcp aberta\n" "$port"
            fi
        fi
        # Independentemente do modo JSON, registra a porta aberta no arquivo temporário.
        # Isso é usado para o resumo final e para o resumo em caso de interrupção (Ctrl+C).
        echo "$port" >> "$tmp_file"
    fi
}
export -f scan_port_job # Exporta a função para que esteja disponível nos subshells dos jobs paralelos.

# --- Processamento de Argumentos da Linha de Comando ---
ORIGINAL_TARGET_HOST=""
PORT_RANGE_RAW=""
TIMEOUT_SECONDS=$DEFAULT_TIMEOUT_SECONDS
PARALLEL_JOBS=$DEFAULT_PARALLEL_JOBS

# Parseia os argumentos da linha de comando.
args=() # Array para armazenar argumentos posicionais.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)
            # Valida se o argumento para --timeout foi fornecido.
            if [[ -z "$2" ]]; then if ! $OUTPUT_JSON; then echo "[!] Erro: Opção --timeout requer um argumento." >&2; fi; show_help; exit 1; fi
            TIMEOUT_SECONDS="$2"; shift 2 ;;
        --parallel)
            # Valida se o argumento para --parallel foi fornecido.
            if [[ -z "$2" ]]; then if ! $OUTPUT_JSON; then echo "[!] Erro: Opção --parallel requer um argumento." >&2; fi; show_help; exit 1; fi
            PARALLEL_JOBS="$2"; shift 2 ;;
        --json)
            OUTPUT_JSON=true; shift 1 ;;
        --force-netcat)
            FORCE_USE_NETCAT=true; shift 1 ;;
        -h|--help)
            show_help; exit 0 ;;
        -*|--*)
            # Opção desconhecida.
            if ! $OUTPUT_JSON; then echo "[!] Erro: Opção desconhecida: $1" >&2; fi; show_help; exit 1 ;;
        *)
            # Argumento posicional (host ou faixa de portas).
            args+=("$1"); shift ;;
    esac
done

# Atribui os argumentos posicionais às variáveis correspondentes.
ORIGINAL_TARGET_HOST=${args[0]}
PORT_RANGE_RAW=${args[1]} # Pode estar vazio se não for fornecido.

# Valida se o host do alvo foi especificado (obrigatório).
if [ -z "$ORIGINAL_TARGET_HOST" ]; then
    if ! $OUTPUT_JSON; then echo "[!] Erro: O host do alvo não foi especificado." >&2; fi; show_help; exit 1
fi

# Valida os valores de timeout e paralelismo.
validate_positive_integer "$TIMEOUT_SECONDS" "Timeout"
validate_positive_integer "$PARALLEL_JOBS" "Nível de paralelismo"

# Define a faixa de portas a ser usada (fornecida ou padrão).
PORT_RANGE_INPUT=${PORT_RANGE_RAW:-$DEFAULT_PORT_RANGE}

# --- Configurar Tratamento de Sinais e Arquivo Temporário ---
# Cria um arquivo temporário seguro para armazenar as portas abertas.
TMP_OPEN_PORTS_FILE=$(mktemp)
# Configura um trap para garantir que o arquivo temporário seja removido na saída do script (normal, erro ou Ctrl+C).
# O trap para EXIT é executado em qualquer saída, exceto `kill -9`.
trap "rm -f $TMP_OPEN_PORTS_FILE" EXIT
# Configura um trap para SIGINT (Ctrl+C) e SIGTERM para chamar a função handle_interrupt.
trap handle_interrupt SIGINT SIGTERM

# --- Determinar Método de Varredura e Resolução DNS ---
ACTUAL_SCAN_METHOD="devtcp" # Método de varredura padrão é /dev/tcp.
DEV_TCP_USABLE=true       # Flag indicando se /dev/tcp é funcional.

# Verifica se /dev/tcp é funcional. Tenta uma conexão com timeout curto a uma porta improvável.
# Se o erro for "No such file or directory" ou similar, /dev/tcp não é suportado.
dev_tcp_error_check_output=$( (timeout 0.2s bash -c "exec 3<> /dev/tcp/localhost/65534") 2>&1 )
if [[ "$dev_tcp_error_check_output" == *"No such file or directory"* || \
      "$dev_tcp_error_check_output" == *"Bad file descriptor"* || \
      "$dev_tcp_error_check_output" == *"Invalid argument"* ]]; then # Algumas shells podem dar outros erros.
    DEV_TCP_USABLE=false
fi
# Tenta fechar o descritor de arquivo, caso tenha sido aberto, ignorando erros.
(exec 3<&-) &>/dev/null 
(exec 3>&-) &>/dev/null

# Decide qual método de varredura usar com base na disponibilidade e opções do usuário.
if $FORCE_USE_NETCAT; then # Se o usuário forçou o uso de netcat.
    if command -v nc &>/dev/null; then # Verifica se netcat (nc) está instalado.
        ACTUAL_SCAN_METHOD="netcat"
    else
        if ! $OUTPUT_JSON; then echo "[!] Erro: --force-netcat especificado, mas netcat (nc) não encontrado." >&2; fi
        exit 1
    fi
elif ! $DEV_TCP_USABLE; then # Se /dev/tcp não for funcional.
    if ! $OUTPUT_JSON; then echo "[!] Aviso: /dev/tcp parece não estar funcional. Tentando usar netcat como fallback." >&2; fi
    if command -v nc &>/dev/null; then # Verifica se netcat (nc) está instalado.
        ACTUAL_SCAN_METHOD="netcat"
    else
        if ! $OUTPUT_JSON; then echo "[!] Erro: /dev/tcp não está funcional e netcat (nc) não foi encontrado." >&2; fi
        exit 1
    fi
fi
export ACTUAL_SCAN_METHOD # Exporta para que esteja disponível nos subshells dos jobs paralelos.

# --- Resolução de DNS ---
# Tenta resolver o hostname para um endereço IP.
# Isso é útil para exibir o endereço IP real que está sendo escaneado.
TARGET_IP=""
if command -v dig &>/dev/null; then # Tenta usar dig para resolução de DNS.
    TARGET_IP=$(dig +short "$ORIGINAL_TARGET_HOST" A | head -n1)
elif command -v host &>/dev/null; then # Tenta usar host para resolução de DNS.
    TARGET_IP=$(host -t A "$ORIGINAL_TARGET_HOST" | grep "has address" | head -n1 | awk '{print $NF}')
elif command -v nslookup &>/dev/null; then # Tenta usar nslookup para resolução de DNS.
    TARGET_IP=$(nslookup "$ORIGINAL_TARGET_HOST" | grep -A1 "Name:" | grep "Address:" | head -n1 | awk '{print $NF}')
fi

# Se não conseguiu resolver o hostname para um IP, avisa o usuário.
if [ -z "$TARGET_IP" ]; then
    if ! $OUTPUT_JSON; then echo "[!] Aviso: Não foi possível resolver $ORIGINAL_TARGET_HOST. Tentando escanear usando $ORIGINAL_TARGET_HOST diretamente." >&2; fi
    TARGET_IP="$ORIGINAL_TARGET_HOST" # Usa o hostname original como fallback.
fi

# --- Gerar Lista de Portas para Varredura ---
# Gera a lista de portas a serem escaneadas usando a função parse_ports.
# Armazena em um array para uso posterior.
readarray -t PORTS_TO_SCAN < <(parse_ports "$PORT_RANGE_INPUT")
TOTAL_PORTS_TO_SCAN=${#PORTS_TO_SCAN[@]}

# Verifica se há portas válidas para escanear.
if [ "$TOTAL_PORTS_TO_SCAN" -eq 0 ]; then
    if ! $OUTPUT_JSON; then echo "[!] Nenhuma porta válida para escanear." >&2; fi
    exit 1
fi
TOTAL_PORTS_TO_SCAN_FOR_SUMMARY=$TOTAL_PORTS_TO_SCAN # Armazena para uso no resumo.

# --- Exibir Informações Iniciais ---
# Exibe informações sobre a varredura que será realizada.
if ! $OUTPUT_JSON; then
    echo "[*] Escaneando alvo: $ORIGINAL_TARGET_HOST"
    if [ "$ORIGINAL_TARGET_HOST" != "$TARGET_IP" ]; then
        echo "[*] Endereço IP resolvido: $TARGET_IP"
    fi
    echo "[*] Faixa de portas: $PORT_RANGE_INPUT"
    echo "[*] Método de varredura: $ACTUAL_SCAN_METHOD"
    echo "[*] Timeout por porta: ${TIMEOUT_SECONDS}s, Paralelismo: $PARALLEL_JOBS jobs"
fi

# --- Iniciar Varredura ---
# Registra o timestamp de início da varredura para cálculo de duração.
SCAN_START_TIME_NS=$(date +%s%N)

# Inicializa o array para armazenar as portas abertas encontradas.
declare -a OPEN_PORTS=()

# Inicializa o contador de jobs em execução.
RUNNING_JOBS=0

# Itera sobre cada porta a ser escaneada.
for port in "${PORTS_TO_SCAN[@]}"; do
    # Verifica se já atingiu o limite de jobs paralelos.
    if [ "$RUNNING_JOBS" -ge "$PARALLEL_JOBS" ]; then
        # Espera por um job terminar antes de iniciar o próximo.
        wait -n
        RUNNING_JOBS=$((RUNNING_JOBS - 1))
    fi
    
    # Inicia um novo job de varredura em background.
    scan_port_job "$TARGET_IP" "$port" "$TIMEOUT_SECONDS" "$TMP_OPEN_PORTS_FILE" "$OUTPUT_JSON" &
    
    # Armazena o PID do job para gerenciamento posterior.
    CHILD_PID=$!
    CHILD_PIDS+=("$CHILD_PID")
    
    # Incrementa o contador de jobs em execução.
    RUNNING_JOBS=$((RUNNING_JOBS + 1))
done

# Espera todos os jobs de varredura terminarem.
wait

# --- Processar Resultados ---
# Lê as portas abertas encontradas do arquivo temporário.
if [ -f "$TMP_OPEN_PORTS_FILE" ] && [ -s "$TMP_OPEN_PORTS_FILE" ]; then
    readarray -t OPEN_PORTS < <(sort -n "$TMP_OPEN_PORTS_FILE" | uniq)
fi

# Calcula o tempo total de varredura.
SCAN_END_TIME_NS=$(date +%s%N)
SCAN_DURATION_NS=$((SCAN_END_TIME_NS - SCAN_START_TIME_NS))
SCAN_DURATION_S_FORMATTED=$(printf "%.1f" $(echo "scale=1; $SCAN_DURATION_NS / 1000000000" | bc -l))

# --- Exibir Resultados ---
# Exibe os resultados da varredura no formato apropriado (texto ou JSON).
if $OUTPUT_JSON; then
    # Formata os resultados como JSON.
    echo "{"
    echo "  \"target\": \"$ORIGINAL_TARGET_HOST\","
    if [ "$ORIGINAL_TARGET_HOST" != "$TARGET_IP" ]; then
        echo "  \"ip\": \"$TARGET_IP\","
    fi
    echo "  \"scan_method\": \"$ACTUAL_SCAN_METHOD\","
    echo "  \"port_range\": \"$PORT_RANGE_INPUT\","
    echo "  \"timeout\": $TIMEOUT_SECONDS,"
    echo "  \"parallel_jobs\": $PARALLEL_JOBS,"
    echo "  \"duration_seconds\": $SCAN_DURATION_S_FORMATTED,"
    echo "  \"total_ports_scanned\": $TOTAL_PORTS_TO_SCAN,"
    echo "  \"open_ports\": ["
    
    # Adiciona cada porta aberta ao JSON.
    for i in "${!OPEN_PORTS[@]}"; do
        port=${OPEN_PORTS[$i]}
        service=$(get_service_name "$port")
        echo -n "    {\"port\": $port"
        if [ -n "$service" ]; then
            echo -n ", \"service\": \"$service\""
        fi
        if [ $i -eq $((${#OPEN_PORTS[@]} - 1)) ]; then
            echo "}"
        else
            echo "},"
        fi
    done
    
    echo "  ]"
    echo "}"
else
    # Exibe um resumo em formato texto.
    echo ""
    echo "[*] Varredura concluída em ${SCAN_DURATION_S_FORMATTED}s"
    echo "[*] Total de portas escaneadas: $TOTAL_PORTS_TO_SCAN"
    
    if [ ${#OPEN_PORTS[@]} -eq 0 ]; then
        echo "[*] Nenhuma porta aberta encontrada."
    else
        echo "[*] Portas abertas encontradas: ${#OPEN_PORTS[@]}"
        for port in "${OPEN_PORTS[@]}"; do
            service=$(get_service_name "$port")
            if [ -n "$service" ]; then
                echo "[+] Porta $port/tcp aberta ($service)"
            else
                echo "[+] Porta $port/tcp aberta"
            fi
        done
    fi
fi

# Limpa o arquivo temporário (embora o trap EXIT já faça isso).
if [ -n "$TMP_OPEN_PORTS_FILE" ] && [ -f "$TMP_OPEN_PORTS_FILE" ]; then
    rm -f "$TMP_OPEN_PORTS_FILE"
fi

# Sai com código de sucesso.
exit 0
