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
echo -e "${P} █ JITTER PANEL SSH v3.1 - INSTALADOR █${N}"
echo -e "${V}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""

echo -e " ${B}▸${N} ${W}Instalando dependencias...${N}"
apt update -y >/dev/null 2>&1
apt install -y curl wget net-tools ufw openssh-server dropbear stunnel4 squid >/dev/null 2>&1

echo -e " ${B}▸${N} ${W}Configurando estructura...${N}"
mkdir -p /etc/jitterpanel /var/log/jitterpanel

# ── CREAR EL MENÚ ADMIN ──────────────────────────────────────
cat > /usr/bin/menu << 'MENU'
#!/bin/bash
# COLORES
P='\033[0;35m'; V='\033[1;35m'; R='\033[0;91m'; G='\033[0;92m'
Y='\033[1;93m'; B='\033[0;94m'; C='\033[0;96m'; W='\033[1;97m'; N='\033[0m'

[[ $(id -u)!= 0 ]] && { echo -e "${R}Ejecutar como root: sudo menu${N}"; exit 1; }

pausa() {
    echo ""
    read -p " Presiona ENTER para continuar..."
}

banner() {
    clear
    echo -e "${V}"
    echo ' ██╗██╗████████╗████████╗███████╗██████╗'
    echo ' ██║██║╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗'
    echo ' ██║██║ ██║ ██║ █████╗ ██████╔╝'
    echo ' ██ ██║██║ ██║ ██║ ██╔══╝ ██╔══██╗'
    echo ' ╚█████╔╝██║ ██║ ██║ ███████╗██║ ██║'
    echo ' ╚════╝ ╚═╝ ╚═╝ ╚═╝ ╚══════╝╚═╝ ╚═╝'
    echo -e "${P} █ JITTER PANEL SSH v3.1 █${N}"
    echo -e "${V}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    echo -e " ${W}IP: ${C}$(curl -s ifconfig.me)${N} ${W}OS: ${C}$(lsb_release -ds 2>/dev/null)${N}"
    echo -e "${V}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
}

crear_usuario() {
    banner
    echo -e "${P}[1] CREAR USUARIO SSH${N}"
    echo ""
    read -p " ${B}▸${N} ${W}Usuario: ${N}" user
    [[ -z "$user" ]] && { echo -e " ${R}Usuario vacío${N}"; pausa; return; }
    read -p " ${B}▸${N} ${W}Contraseña: ${N}" pass
    read -p " ${B}▸${N} ${W}Días para expirar: ${N}" dias
    read -p " ${B}▸${N} ${W}Límite de conexiones: ${N}" limit

    dias=${dias:-30}
    limit=${limit:-1}
    exp=$(date -d "+$dias days" +"%Y-%m-%d")

    useradd -M -s /bin/false -e "$exp" "$user" 2>/dev/null
    echo "$user:$pass" | chpasswd
    echo "$user $limit" >> /etc/jitterpanel/limites

    echo ""
    echo -e " ${G}✓ Usuario creado${N}"
    echo -e " ${W}Usuario:${N} $user"
    echo -e " ${W}Clave:${N} $pass"
    echo -e " ${W}Expira:${N} $exp"
    echo -e " ${W}Límite:${N} $limit"
    pausa
}

eliminar_usuario() {
    banner
    echo -e "${P}[2] ELIMINAR USUARIO${N}"
    echo ""
    echo -e "${W}Usuarios activos:${N}"
    cut -d: -f1 /etc/passwd | grep -vE '^(root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|nobody|systemd|messagebus|syslog|_apt|lxd|uuidd|dnsmasq|landscape|pollinate|sshd)' | nl
    echo ""
    read -p " ${B}▸${N} ${W}Usuario a eliminar: ${N}" user
    [[ -z "$user" ]] && { pausa; return; }

    pkill -u "$user" 2>/dev/null
    userdel "$user" 2>/dev/null
    sed -i "/^$user /d" /etc/jitterpanel/limites

    echo -e " ${G}✓ Usuario $user eliminado${N}"
    pausa
}

listar_usuarios() {
    banner
    echo -e "${P}[3] USUARIOS CONECTADOS${N}"
    echo ""
    printf "${W}%-15s %-10s %-10s %-15s${N}\n" "USUARIO" "LIMITE" "CONECTADOS" "EXPIRA"
    echo -e "${V}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"

    while IFS= read -r line; do
        user=$(echo "$line" | cut -d: -f1)
        exp=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2)
        limit=$(grep "^$user " /etc/jitterpanel/limites 2>/dev/null | awk '{print $2}')
        limit=${limit:-0}
        online=$(ps -u "$user" | grep -c sshd)
        printf "%-15s %-10s %-10s %-15s\n" "$user" "$limit" "$online" "$exp"
    done < <(cut -d: -f1 /etc/passwd | grep -vE '^(root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|nobody|systemd|messagebus|syslog|_apt|lxd|uuidd|dnsmasq|landscape|pollinate|sshd)')
    pausa
}

cambiar_puerto() {
    banner
    echo -e "${P}[4] CAMBIAR PUERTOS${N}"
    echo ""
    echo -e " ${W}1.${N} SSH: $(grep Port /etc/ssh/sshd_config | awk '{print $2}' | head -1)"
    echo -e " ${W}2.${N} Dropbear: $(grep DROPBEAR_PORT /etc/default/dropbear | cut -d= -f2)"
    echo -e " ${W}3.${N} SSL: $(grep accept /etc/stunnel/stunnel.conf 2>/dev/null | awk '{print $3}' | head -1)"
    echo ""
    read -p " ${B}▸${N} ${W}Opción [1-3]: ${N}" opt
    read -p " ${B}▸${N} ${W}Nuevo puerto: ${N}" puerto

    case $opt in
        1) sed -i "s/Port.*/Port $puerto/" /etc/ssh/sshd_config
           ufw allow $puerto/tcp >/dev/null 2>&1
           systemctl restart sshd ;;
        2) sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=$puerto/" /etc/default/dropbear
           ufw allow $puerto/tcp >/dev/null 2>&1
           systemctl restart dropbear ;;
        3) sed -i "s/accept =.*/accept = $puerto/" /etc/stunnel/stunnel.conf
           ufw allow $puerto/tcp >/dev/null 2>&1
           systemctl restart stunnel4 ;;
    esac
    echo -e " ${G}✓ Puerto cambiado a $puerto${N}"
    pausa
}

cambiar_banner() {
    banner
    echo -e "${P}[5] CAMBIAR BANNER SSH${N}"
    echo ""
    echo -e " ${W}Pega tu banner y termina con CTRL+D:${N}"
    cat > /etc/jitterpanel/banner
    echo "Banner /etc/jitterpanel/banner" >> /etc/ssh/sshd_config
    systemctl restart sshd
    echo -e " ${G}✓ Banner actualizado${N}"
    pausa
}

ver_ip() {
    banner
    echo -e "${P}[6] INFORMACIÓN DEL VPS${N}"
    echo ""
    echo -e " ${W}IP Pública:${N} ${C}$(curl -s ifconfig.me)${N}"
    echo -e " ${W}IP Local:${N} ${C}$(hostname -I | awk '{print $1}')${N}"
    echo -e " ${W}Hostname:${N} ${C}$(hostname)${N}"
    echo -e " ${W}Uptime:${N} ${C}$(uptime -p)${N}"
    echo -e " ${W}OS:${N} ${C}$(lsb_release -ds 2>/dev/null)${N}"
    pausa
}

# MENU PRINCIPAL
while true; do
    banner
    echo -e "${P}[1]${N} ${W}Crear usuario SSH${N}"
    echo -e "${P}[2]${N} ${W}Eliminar usuario${N}"
    echo -e "${P}[3]${N} ${W}Listar usuarios conectados${N}"
    echo -e "${P}[4]${N} ${W}Cambiar puertos${N}"
    echo -e "${P}[5]${N} ${W}Cambiar Banner SSH${N}"
    echo -e "${P}[6]${N} ${W}Ver IP/Info del VPS${N}"
    echo -e "${P}[0]${N} ${R}Salir${N}"
    echo -e "${V}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    read -p " ${B}▸${N} ${W}Opción: ${N}" opcao

    case $opcao in
        1) crear_usuario ;;
        2) eliminar_usuario ;;
        3) listar_usuarios ;;
        4) cambiar_puerto ;;
        5) cambiar_banner ;;
        6) ver_ip ;;
        0) exit 0 ;;
        *) echo -e " ${R}Opción inválida${N}"; sleep 1 ;;
    esac
done
MENU

chmod +x /usr/bin/menu
ln -sf /usr/bin/menu_admin 2>/dev/null

# CONFIGURAR SSH
sed -i 's/#Port 22/Port 22/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# FIREWALL
ufw allow 22/tcp >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

echo ""
echo -e "${V}╔══════════════════════════════════════════════════════════════╗${N}"
echo -e "${V}║${N} ${W}✓ INSTALACIÓN COMPLETADA${N} ${V}║${N}"
echo -e "${V}╠══════════════════════════════════════════════════════════════╣${N}"
echo -e "${V}║${N} ${W}Usa el comando:${N} ${C}sudo menu${N} ${V}║${N}"
echo -e "${V}║${N} ${W}o también:${N} ${C}menu${N} ${V}║${N}"
echo -e "${V}╚══════════════════════════════════════════════════════════════╝${N}"
echo ""
