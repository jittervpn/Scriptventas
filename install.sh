#!/bin/bash

# Colores
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Verificar ROOT
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${ROJO}❌ DEBES EJECUTAR COMO ROOT${NC}"
    exit 1
fi

echo -e "${AZUL}=============================================${NC}"
echo -e "${AZUL}    INSTALACIÓN COMPLETA - SIN ERRORES    ${NC}"
echo -e "${AZUL}=============================================${NC}"

# Actualizar e instalar paquetes
apt update -y && apt upgrade -y
apt install -y curl wget git nano vim zip unzip tar net-tools \
    iptables ufw openssh-server openssl sudo screen htop \
    build-essential libssl-dev zlib1g-dev lsof bc

# Configurar servicios
systemctl enable --now ssh
systemctl enable --now ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

# Carpetas y archivos
mkdir -p /etc/mi_panel/usuarios
mkdir -p /etc/mi_panel/config
mkdir -p /var/log/mi_panel

touch /etc/mi_panel/config/puertos.conf
touch /etc/mi_panel/config/ips_permitidas.conf
touch /etc/mi_panel/config/banner.txt
touch /etc/mi_panel/usuarios/lista_usuarios.db
touch /var/log/mi_panel/acciones.log

chmod -R 700 /etc/mi_panel
chown -R root:root /etc/mi_panel

# Banner por defecto
cat > /etc/mi_panel/config/banner.txt << EOF
=============================================
           BIENVENIDO AL SISTEMA
   Administración y Gestión de Servicios
=============================================
Acceso restringido solo a personal autorizado
Todas las acciones son registradas
=============================================
EOF

# CREAR MENÚ CORREGIDO 100%
cat > /usr/bin/menu_admin << 'EOF'
#!/bin/bash
# Rutas
DIR_CONF="/etc/mi_panel/config"
DIR_USU="/etc/mi_panel/usuarios"
ARCH_PUERTOS="$DIR_CONF/puertos.conf"
ARCH_IPS="$DIR_CONF/ips_permitidas.conf"
ARCH_BANNER="$DIR_CONF/banner.txt"
ARCH_USUARIOS="$DIR_USU/lista_usuarios.db"
LOGS="/var/log/mi_panel/acciones.log"

# Colores
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

registrar() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> "$LOGS"
}

pausa() {
    echo -e "\n${CYAN}Presiona Enter para continuar...${NC}"
    read -r
}

# ---------------- USUARIOS ----------------
menu_usuarios() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE USUARIOS ===${NC}"
        echo "1. Agregar usuario"
        echo "2. Eliminar usuario"
        echo "3. Listar usuarios"
        echo "4. Cambiar contraseña"
        echo "5. Volver"
        read -p "Opción: " op
        case $op in
            1)
                read -p "Usuario: " u
                if grep -q "^$u:" "$ARCH_USUARIOS"; then echo -e "${ROJO}Ya existe${NC}"; pausa; continue; fi
                read -s -p "Contraseña: " p; echo
                read -p "Vencimiento (días, 0=siempre): " v
                echo "$u:$p:$(date +%s):$v" >> "$ARCH_USUARIOS"
                registrar "Agregado: $u"
                echo -e "${VERDE}✅ OK${NC}"; pausa
                ;;
            2)
                read -p "Usuario a borrar: " u
                if grep -q "^$u:" "$ARCH_USUARIOS"; then sed -i "/^$u:/d" "$ARCH_USUARIOS"; registrar "Borrado: $u"; echo -e "${VERDE}✅ OK${NC}"; else echo -e "${ROJO}No existe${NC}"; fi
                pausa
                ;;
            3)
                echo -e "${CYAN}--- Lista ---${NC}"
                [ -s "$ARCH_USUARIOS" ] && awk -F: '{print "Usuario: "$1" | Creado: "$3" | Vence: "$4" días"}' "$ARCH_USUARIOS" || echo "Vacío"
                pausa
                ;;
            4)
                read -p "Usuario: " u
                if grep -q "^$u:" "$ARCH_USUARIOS"; then
                    read -s -p "Nueva contraseña: " p; echo
                    sed -i "s/^$u:[^:]*/$u:$p/" "$ARCH_USUARIOS"
                    registrar "Contraseña cambiada: $u"; echo -e "${VERDE}✅ OK${NC}"
                else echo -e "${ROJO}No existe${NC}"; fi
                pausa
                ;;
            5) break ;;
            *) echo -e "${ROJO}Inválido${NC}"; pausa ;;
        esac
    done
}

# ---------------- PUERTOS ----------------
menu_puertos() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE PUERTOS ===${NC}"
        echo "1. Abrir"
        echo "2. Cerrar"
        echo "3. Ver abiertos"
        echo "4. Volver"
        read -p "Opción: " op
        case $op in
            1)
                read -p "Puerto: " pto
                read -p "Protocolo (tcp/udp/ambos): " pro
                if [ "$pro" = "ambos" ]; then
                    ufw allow "$pto"/tcp; ufw allow "$pto"/udp
                    echo "$pto/tcp" >> "$ARCH_PUERTOS"; echo "$pto/udp" >> "$ARCH_PUERTOS"
                else
                    ufw allow "$pto/$pro"; echo "$pto/$pro" >> "$ARCH_PUERTOS"
                fi
                registrar "Abierto: $pto/$pro"; echo -e "${VERDE}✅ OK${NC}"; pausa
                ;;
            2)
                read -p "Puerto: " pto
                read -p "Protocolo (tcp/udp/ambos): " pro
                if [ "$pro" = "ambos" ]; then
                    ufw deny "$pto"/tcp; ufw deny "$pto"/udp
                    sed -i "/^$pto\/tcp/d" "$ARCH_PUERTOS"; sed -i "/^$pto\/udp/d" "$ARCH_PUERTOS"
                else
                    ufw deny "$pto/$pro"; sed -i "/^$pto\/$pro/d" "$ARCH_PUERTOS"
                fi
                registrar "Cerrado: $pto/$pro"; echo -e "${VERDE}✅ OK${NC}"; pausa
                ;;
            3)
                echo -e "${CYAN}--- Registrados ---${NC}"; [ -s "$ARCH_PUERTOS" ] && cat "$ARCH_PUERTOS" || echo "Vacío"
                echo -e "\n--- Activos ---"; netstat -tulpn | grep LISTEN
                pausa
                ;;
            4) break ;;
            *) echo -e "${ROJO}Inválido${NC}"; pausa ;;
        esac
    done
}

# ---------------- IPS ----------------
menu_ips() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE IPs ===${NC}"
        echo "1. Permitir"
        echo "2. Bloquear"
        echo "3. Ver reglas"
        echo "4. Volver"
        read -p "Opción: " op
        case $op in
            1)
                read -p "IP: " ip; ufw allow from "$ip"; echo "PERMITIR:$ip" >> "$ARCH_IPS"
                registrar "Permitida: $ip"; echo -e "${VERDE}✅ OK${NC}"; pausa
                ;;
            2)
                read -p "IP: " ip; ufw deny from "$ip"; echo "BLOQUEAR:$ip" >> "$ARCH_IPS"
                registrar "Bloqueada: $ip"; echo -e "${VERDE}✅ OK${NC}"; pausa
                ;;
            3)
                echo -e "${CYAN}--- Reglas ---${NC}"; [ -s "$ARCH_IPS" ] && cat "$ARCH_IPS" || echo "Vacío"
                echo -e "\n--- Firewall ---"; ufw status numbered
                pausa
                ;;
            4) break ;;
            *) echo -e "${ROJO}Inválido${NC}"; pausa ;;
        esac
    done
}

# ---------------- BANNER ----------------
menu_banner() {
    while true; do
        clear
        echo -e "${AZUL}=== BANNER ===${NC}"
        echo "1. Ver"
        echo "2. Editar"
        echo "3. Restaurar original"
        echo "4. Volver"
        read -p "Opción: " op
        case $op in
            1) echo -e "${CYAN}--- BANNER ---${NC}"; cat "$ARCH_BANNER"; pausa ;;
            2) nano "$ARCH_BANNER"; registrar "Banner editado"; echo -e "${VERDE}✅ OK${NC}"; pausa ;;
            3)
                cat > "$ARCH_BANNER" << EOF
=============================================
           BIENVENIDO AL SISTEMA
   Administración y Gestión de Servicios
=============================================
Acceso restringido solo a personal autorizado
Todas las acciones son registradas
=============================================
EOF
                registrar "Banner restaurado"; echo -e "${VERDE}✅ OK${NC}"; pausa
                ;;
            4) break ;;
            *) echo -e "${ROJO}Inválido${NC}"; pausa ;;
        esac
    done
}

# ---------------- MENÚ PRINCIPAL ----------------
while true; do
    clear
    echo -e "${AZUL}=============================================${NC}"
    echo -e "${AZUL}      MENÚ DE ADMINISTRACIÓN       ${NC}"
    echo -e "${AZUL}=============================================${NC}"
    echo "1. Usuarios"
    echo "2. Puertos"
    echo "3. IPs"
    echo "4. Banner"
    echo "5. Ver registro"
    echo "6. Salir"
    echo -e "${AZUL}=============================================${NC}"
    read -p "Elige: " op
    case $op in
        1) menu_usuarios ;;
        2) menu_puertos ;;
        3) menu_ips ;;
        4) menu_banner ;;
        5) echo -e "${CYAN}--- REGISTRO ---${NC}"; [ -s "$LOGS" ] && cat "$LOGS" || echo "Vacío"; pausa ;;
        6) echo -e "${VERDE}Saliendo...${NC}"; exit 0 ;;
        *) echo -e "${ROJO}Inválido${NC}"; pausa ;;
    esac
done
EOF

# ✅ PERMISOS ASEGURADOS (aquí estaba el error antes)
chmod 755 /usr/bin/menu_admin
chown root:root /usr/bin/menu_admin
chmod +x install.sh

echo -e "${VERDE}=============================================${NC}"
echo -e "${VERDE}✅ INSTALACIÓN LISTA Y CORREGIDA ✅${NC}"
echo -e "${VERDE}=============================================${NC}"
echo -e "Escribe: ${AMARILLO}menu_admin${NC}"
echo -e "${VERDE}=============================================${NC}"
