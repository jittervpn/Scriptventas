#!/bin/bash
# ============================================================
#   JITTER - Banner del Sistema
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'
BOLD='\033[1m'

# Obtener info del sistema
get_info() {
    IP_PUB=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 ip.sb 2>/dev/null || echo "N/A")
    OS=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
    ARCH=$(uname -m)
    CPUS=$(nproc)
    FECHA=$(date '+%d/%m/%Y-%H:%M')
    
    # RAM
    RAM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    RAM_USED=$(free -m | awk '/Mem:/ {print $3}')
    RAM_PCT=$(awk "BEGIN {printf \"%.1f\", ($RAM_USED/$RAM_TOTAL)*100}")
    
    # CPU
    CPU_USE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
    
    # Disco
    DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    DISK_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    # Uptime
    UPTIME=$(uptime -p | sed 's/up //')
}

# Contar usuarios SSH activos
ssh_users() {
    who | grep -v "^$" | wc -l
}

# Estado de servicios
svc_status() {
    local svc=$1
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${GREEN}[ON]${NC}"
    else
        echo -e "${RED}[OFF]${NC}"
    fi
}

# Puerto activo
port_status() {
    local port=$1
    if ss -tlnp 2>/dev/null | grep -q ":$port " || ss -tlnp 2>/dev/null | grep -q ":$port$"; then
        echo -e "${GREEN}$port${NC}"
    else
        echo -e "${RED}$port${NC}"
    fi
}

show_banner() {
    get_info
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}${BOLD}"
    cat << "LOGO"
   #!/bin/bash
# ================================================================
# JITTER PANEL SSH v3.1 - INSTALADOR COMPLETO
# Menú: Usuarios, Puertos, IP, Banner, BadVPN, SSL, etc
# ================================================================

[[ $(id -u)!= 0 ]] && { echo "Ejecutar como root"; exit 1; }

# COLORES
P='\033[0;35m'; V='\033[1;35m'; R='\033[0;91m'; G='\033[0;92m'
Y='\033[1;93m'; B='\033[0;94m'; C='\033[0;96m'; W='\033[1;97m'
N='\033[0m'

clear
echo -e "${V}"
cat << 'LOGO'
      ██╗██╗████████╗████████╗███████╗██████╗
      ██║██║╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗
      ██║██║ ██║ ██║ █████╗ ██████╔╝
 ██ ██║██║ ██║ ██║ ██╔══╝ ██╔══██╗
 ╚█████╔╝██║ ██║ ██║ ███████╗██║ ██║
  ╚════╝ ╚═╝ ╚═╝ ╚═╝ ╚══════╝╚═╝ ╚═╝
LOGO
    echo -e "${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Info sistema — columna izquierda y derecha
    printf " ${YELLOW}S.O:${NC} %-22s ${YELLOW}Arch:${NC} %-12s ${YELLOW}CPU's:${NC}%s\n" \
        "$(echo $OS | cut -c1-22)" "$ARCH" "$CPUS"
    printf " ${YELLOW}IP:${NC}  %-22s ${YELLOW}Fecha:${NC}%s\n" "$IP_PUB" "$FECHA"
    
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    
    # RAM y CPU en barra visual
    printf " ${WHITE}RAM:${NC} ${CYAN}%sMB${NC}/${CYAN}%sMB${NC} (${YELLOW}%s%%${NC})   ${WHITE}CPU:${NC} ${YELLOW}%s%%${NC}   ${WHITE}Uptime:${NC} ${GRAY}%s${NC}\n" \
        "$RAM_USED" "$RAM_TOTAL" "$RAM_PCT" "$CPU_USE" "$UPTIME"
    printf " ${WHITE}Disco:${NC} ${CYAN}%s${NC}/${CYAN}%s${NC} usado (${YELLOW}%s%%${NC})   ${WHITE}Usuarios SSH:${NC} ${GREEN}$(ssh_users)${NC}\n" \
        "$DISK_USED" "$DISK_TOTAL" "$DISK_PCT"
    
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    
    # Servicios y puertos
    local SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [[ -z "$SSH_PORT" ]] && SSH_PORT="22"
    local SSHWS_PORT=$(grep "SSHWS_PORT" /etc/gtkvpn/config.conf 2>/dev/null | cut -d= -f2)
    [[ -z "$SSHWS_PORT" ]] && SSHWS_PORT="80"
    local SSL_PORT=$(grep "SSL_PORT" /etc/gtkvpn/config.conf 2>/dev/null | cut -d= -f2)
    [[ -z "$SSL_PORT" ]] && SSL_PORT="443"
    local XRAY_PORT=$(grep "XRAY_PORT" /etc/gtkvpn/config.conf 2>/dev/null | cut -d= -f2)
    [[ -z "$XRAY_PORT" ]] && XRAY_PORT="32595"
    local SOCKS_PORT=$(grep "SOCKS_PORT" /etc/gtkvpn/config.conf 2>/dev/null | cut -d= -f2)
    [[ -z "$SOCKS_PORT" ]] && SOCKS_PORT="8080"
    
    printf " ${YELLOW}SSH:${NC} %-6s${CYAN}•${NC} ${YELLOW}WEB-NGinx:${NC} %-6s${CYAN}•${NC} ${YELLOW}SSL:${NC} %-6s\n" \
        "$(port_status $SSH_PORT)" "$(port_status $SSHWS_PORT)" "$(port_status $SSL_PORT)"
    printf " ${YELLOW}XRAY/UI:${NC} %-4s${CYAN}•${NC} ${YELLOW}SOCKS5:${NC} %-7s${CYAN}•${NC} ${YELLOW}SlowDNS:${NC} %s\n" \
        "$(port_status $XRAY_PORT)" "$(port_status $SOCKS_PORT)" "$(svc_status slowdns)"
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

show_banner
