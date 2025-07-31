#!/bin/bash

# Scanzy v1.1 - TCP Scanner para Bug Bounty (Stealth + Fingerprint)
# Autor: 404xploit
# Atualizado: 31/07/2025
# Foco: Recon, fingerprint, automação, evasão básica.

DEFAULT_PORT_RANGE="1-1024"
DEFAULT_TIMEOUT_SECONDS=1
DEFAULT_PARALLEL_JOBS=12
DEFAULT_DELAY_MS=50      # Delay random entre scans (stealth)
DEFAULT_PROXY=""         # Proxy chain (ex: socks5://127.0.0.1:9050)
OUTPUT_JSON=false
FORCE_USE_NETCAT=false

declare -a CHILD_PIDS=()
TMP_OPEN_PORTS_FILE=""
SCAN_START_TIME_NS=0

# Banner grabber (simple)
banner_grab() {
    local host="$1"
    local port="$2"
    local banner=""
    # Usa netcat se possível (mais flexível)
    if command -v nc &>/dev/null; then
        banner=$( (echo -e "GET / HTTP/1.0\r\n\r\n"; sleep 1) | nc -w 2 "$host" "$port" 2>/dev/null | head -n 2 | tr -d '\r')
    fi
    echo "$banner"
}

# Service detection estendida
get_service_name() {
    local port="$1"
    case "$port" in
        21) echo "ftp";;
        22) echo "ssh";;
        23) echo "telnet";;
        25) echo "smtp";;
        53) echo "dns";;
        80) echo "http";;
        110) echo "pop3";;
        143) echo "imap";;
        443) echo "https";;
        3306) echo "mysql";;
        3389) echo "rdp";;
        5432) echo "postgresql";;
        5900) echo "vnc";;
        8080) echo "http-proxy";;
        *) echo "";;
    esac
}

show_help() {
    echo "Uso: $0 <host> [porta/faixa] [opções]"
    echo "  --timeout <seg>      Timeout por conexão (default: $DEFAULT_TIMEOUT_SECONDS)"
    echo "  --parallel <N>       Paralelismo (default: $DEFAULT_PARALLEL_JOBS)"
    echo "  --delay <ms>         Delay random entre scans (default: $DEFAULT_DELAY_MS)"
    echo "  --proxy <url>        Proxy chain (ex: socks5://127.0.0.1:9050)"
    echo "  --json               Saída JSON detalhada"
    echo "  --force-netcat       Força netcat"
    echo "  --banner             Faz banner grabbing nas portas abertas"
    echo "  -h, --help           Ajuda"
    echo "Ex: $0 scanme.nmap.org 1-100 --json --banner"
}

validate_positive_integer() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]] || { echo "[!] Valor inválido: $value"; exit 1; }
}

parse_ports() {
    local str="$1"
    if [[ "$str" == *"-"* ]]; then
        seq $(echo "$str" | cut -d- -f1) $(echo "$str" | cut -d- -f2)
    else
        echo "$str"
    fi
}

scan_port_job() {
    local host="$1" port="$2" timeout="$3" tmp_file="$4" output_json="$5" proxy="$6" banner_flag="$7"
    local open=false
    local banner=""
    sleep $((RANDOM % DEFAULT_DELAY_MS))e-3 # random delay stealth

    if [[ -n "$proxy" ]]; then
        if command -v proxychains &>/dev/null; then
            proxychains nc -z -w "$timeout" "$host" "$port" 2>/dev/null && open=true
        fi
    elif [ "$ACTUAL_SCAN_METHOD" == "devtcp" ]; then
        timeout "$timeout"s bash -c "exec 3<> /dev/tcp/$host/$port" 2>/dev/null && open=true
        exec 3<&- 3>&-
    else
        nc -z -w "$timeout" "$host" "$port" 2>/dev/null && open=true
    fi

    if $open; then
        local service=$(get_service_name "$port")
        if [ "$banner_flag" == "true" ]; then
            banner=$(banner_grab "$host" "$port")
        fi
        if ! $output_json; then
            echo "[+] $port/tcp aberta${service:+ ($service)}${banner:+ - $banner}"
        fi
        echo "$port|$service|$banner" >> "$tmp_file"
    fi
}
export -f scan_port_job banner_grab get_service_name

# --- Args ---
ORIGINAL_TARGET_HOST=""
PORT_RANGE_RAW=""
TIMEOUT_SECONDS=$DEFAULT_TIMEOUT_SECONDS
PARALLEL_JOBS=$DEFAULT_PARALLEL_JOBS
DELAY_MS=$DEFAULT_DELAY_MS
PROXY=""
BANNER_FLAG=false

args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) TIMEOUT_SECONDS="$2"; shift 2;;
        --parallel) PARALLEL_JOBS="$2"; shift 2;;
        --delay) DELAY_MS="$2"; shift 2;;
        --proxy) PROXY="$2"; shift 2;;
        --json) OUTPUT_JSON=true; shift;;
        --force-netcat) FORCE_USE_NETCAT=true; shift;;
        --banner) BANNER_FLAG=true; shift;;
        -h|--help) show_help; exit 0;;
        *) args+=("$1"); shift;;
    esac
done

ORIGINAL_TARGET_HOST=${args[0]}
PORT_RANGE_RAW=${args[1]}

[ -z "$ORIGINAL_TARGET_HOST" ] && { echo "[!] Host obrigatório"; exit 1; }
validate_positive_integer "$TIMEOUT_SECONDS"
validate_positive_integer "$PARALLEL_JOBS"

PORT_RANGE_INPUT=${PORT_RANGE_RAW:-$DEFAULT_PORT_RANGE}
TMP_OPEN_PORTS_FILE=$(mktemp)
trap "rm -f $TMP_OPEN_PORTS_FILE" EXIT

# Detecta método scan
ACTUAL_SCAN_METHOD="devtcp"
if $FORCE_USE_NETCAT; then
    ACTUAL_SCAN_METHOD="netcat"
elif ! exec 3<> /dev/tcp/localhost/65534 2>/dev/null; then
    ACTUAL_SCAN_METHOD="netcat"
fi
exec 3<&- 3>&-

TARGET_IP=$(getent hosts "$ORIGINAL_TARGET_HOST" | awk '{print $1}')
[ -z "$TARGET_IP" ] && TARGET_IP="$ORIGINAL_TARGET_HOST"

readarray -t PORTS_TO_SCAN < <(parse_ports "$PORT_RANGE_INPUT")

echo "[*] Scan: $TARGET_IP, Ports: $PORT_RANGE_INPUT, Paralelismo: $PARALLEL_JOBS, Timeout: $TIMEOUT_SECONDS, Proxy: ${PROXY:-none}, Banner: $BANNER_FLAG"
SCAN_START_TIME_NS=$(date +%s%N)

RUNNING_JOBS=0
for port in "${PORTS_TO_SCAN[@]}"; do
    if [ "$RUNNING_JOBS" -ge "$PARALLEL_JOBS" ]; then wait -n; RUNNING_JOBS=$((RUNNING_JOBS - 1)); fi
    scan_port_job "$TARGET_IP" "$port" "$TIMEOUT_SECONDS" "$TMP_OPEN_PORTS_FILE" "$OUTPUT_JSON" "$PROXY" "$BANNER_FLAG" &
    CHILD_PIDS+=("$!")
    RUNNING_JOBS=$((RUNNING_JOBS + 1))
done
wait

readarray -t OPEN_RAW < <(sort -n "$TMP_OPEN_PORTS_FILE" | uniq)
SCAN_END_TIME_NS=$(date +%s%N)
DURATION=$(printf "%.1f" $(echo "scale=1; ($SCAN_END_TIME_NS-$SCAN_START_TIME_NS)/1000000000" | bc -l))

if $OUTPUT_JSON; then
    echo "{"
    echo "  \"target\": \"$ORIGINAL_TARGET_HOST\","
    echo "  \"ip\": \"$TARGET_IP\","
    echo "  \"duration\": $DURATION,"
    echo "  \"ports\": ["
    for i in "${!OPEN_RAW[@]}"; do
        IFS='|' read -r port service banner <<<"${OPEN_RAW[$i]}"
        echo -n "    {\"port\": $port"
        [ -n "$service" ] && echo -n ", \"service\": \"$service\""
        [ -n "$banner" ] && echo -n ", \"banner\": \"$(echo "$banner" | sed 's/"/\\"/g')\""
        echo -n "}"
        [ $i -lt $((${#OPEN_RAW[@]}-1)) ] && echo ","
    done
    echo "  ]"
    echo "}"
else
    echo "[*] Scan concluído em ${DURATION}s. Portas abertas:"
    for raw in "${OPEN_RAW[@]}"; do
        IFS='|' read -r port service banner <<<"$raw"
        echo "[+] $port/tcp${service:+ ($service)}${banner:+ - $banner}"
    done
fi

exit 0
