#!/bin/bash

# Colores para mensajes
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Verificar si es root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${ROJO}❌ Este script debe ejecutarse como root${NC}"
    exit 1
fi

echo -e "${AZUL}=============================================${NC}"
echo -e "${AZUL}    INSTALACIÓN Y CONFIGURACIÓN COMPLETA    ${NC}"
echo -e "${AZUL}=============================================${NC}"

# Actualizar paquetes
echo -e "${AMARILLO}🔄 Actualizando sistema...${NC}"
apt update -y && apt upgrade -y

# Instalar dependencias esenciales
echo -e "${AMARILLO}📦 Instalando paquetes necesarios...${NC}"
apt install -y curl wget git nano vim zip unzip tar net-tools \
    iptables ufw openssh-server openssl sudo screen htop \
    build-essential libssl-dev zlib1g-dev lsof bc

# Habilitar y arrancar servicios básicos
echo -e "${AMARILLO}⚙️ Configurando servicios...${NC}"
systemctl enable --now ssh
systemctl enable --now ufw

# Configurar firewall básico
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

# Crear estructura de carpetas
echo -e "${AMARILLO}📂 Creando estructura de archivos...${NC}"
mkdir -p /etc/mi_panel/usuarios
mkdir -p /etc/mi_panel/config
mkdir -p /var/log/mi_panel

# Archivos de configuración principales
touch /etc/mi_panel/config/puertos.conf
touch /etc/mi_panel/config/ips_permitidas.conf
touch /etc/mi_panel/config/banner.txt
touch /etc/mi_panel/usuarios/lista_usuarios.db
touch /var/log/mi_panel/acciones.log

# Asignar permisos
chmod -R 700 /etc/mi_panel
chown -R root:root /etc/mi_panel

# Banner predeterminado
cat > /etc/mi_panel/config/banner.txt << EOF
=============================================
           BIENVENIDO AL SISTEMA
   Administración y Gestión de Servicios
=============================================
Acceso restringido solo a personal autorizado
Todas las acciones son registradas
=============================================
EOF

# 🧹 BORRAR VERSIONES ANTERIORES (para evitar conflictos)
rm -f /usr/bin/menu_admin
rm -f /usr/bin/menu

# ✅ MENÚ CORREGIDO SIN ERRORES
echo -e "${AMARILLO}📋 Generando menú de administración...${NC}"
cat > /usr/bin/menu_admin << 'EOF'
#!/bin/bash

# Rutas de archivos
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

# Función para registrar acciones
registrar() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> "$LOGS"
}

# Función para pausa (CORREGIDA)
pausa() {
    echo -e "\n${CYAN}Presiona Enter para continuar...${NC}"
    read -r
}

# ==============================
# GESTIÓN DE USUARIOS
# ==============================
menu_usuarios() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE USUARIOS ===${NC}"
        echo "1. Agregar usuario"
        echo "2. Eliminar usuario"
        echo "3. Listar todos los usuarios"
        echo "4. Modificar contraseña"
        echo "5. Volver al menú principal"
        read -p "Selecciona una opción: " op

        case $op in
            1)
                read -p "Nombre de usuario: " usuario
                if grep -q "^$usuario:" "$ARCH_USUARIOS"; then
                    echo -e "${ROJO}❌ El usuario ya existe${NC}"
                    pausa
                    continue
                fi
                read -s -p "Contraseña: " pass
                echo
                read -p "¿Vencimiento (días, 0 = sin límite)?: " venc
                echo "$usuario:$pass:$(date +%s):$venc" >> "$ARCH_USUARIOS"
                registrar "Usuario agregado: $usuario"
                echo -e "${VERDE}✅ Usuario agregado correctamente${NC}"
                pausa
                ;;
            2)
                read -p "Usuario a eliminar: " usuario
                if grep -q "^$usuario:" "$ARCH_USUARIOS"; then
                    sed -i "/^$usuario:/d" "$ARCH_USUARIOS"
                    registrar "Usuario eliminado: $usuario"
                    echo -e "${VERDE}✅ Usuario eliminado${NC}"
                else
                    echo -e "${ROJO}❌ No existe ese usuario${NC}"
                fi
                pausa
                ;;
            3)
                echo -e "${CYAN}--- Lista de Usuarios ---${NC}"
                if [ -s "$ARCH_USUARIOS" ]; then
                    awk -F: '{print "Usuario: "$1" | Creado: "$3" | Vencimiento: "$4" días"}' "$ARCH_USUARIOS"
                else
                    echo "Sin usuarios registrados"
                fi
                pausa
                ;;
            4)
                read -p "Usuario: " usuario
                if grep -q "^$usuario:" "$ARCH_USUARIOS"; then
                    read -s -p "Nueva contraseña: " nueva
                    echo
                    sed -i "s/^$usuario:[^:]*/$usuario:$nueva/" "$ARCH_USUARIOS"
                    registrar "Contraseña modificada: $usuario"
                    echo -e "${VERDE}✅ Contraseña actualizada${NC}"
                else
                    echo -e "${ROJO}❌ Usuario no encontrado${NC}"
                fi
                pausa
                ;;
            5) break ;;
            *) echo -e "${ROJO}❌ Opción inválida${NC}"; pausa ;;
        esac
    done
}

# ==============================
# GESTIÓN DE PUERTOS
# ==============================
menu_puertos() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE PUERTOS ===${NC}"
        echo "1. Abrir puerto"
        echo "2. Cerrar puerto"
        echo "3. Listar puertos abiertos"
        echo "4. Volver al menú principal"
        read -p "Selecciona una opción: " op

        case $op in
            1)
                read -p "Puerto a abrir: " pto
                read -p "Protocolo (tcp/udp/ambos): " proto
                if [ "$proto" = "ambos" ]; then
                    ufw allow "$pto"/tcp
                    ufw allow "$pto"/udp
                    echo "$pto/tcp" >> "$ARCH_PUERTOS"
                    echo "$pto/udp" >> "$ARCH_PUERTOS"
                else
                    ufw allow "$pto/$proto"
                    echo "$pto/$proto" >> "$ARCH_PUERTOS"
                fi
                registrar "Puerto abierto: $pto ($proto)"
                echo -e "${VERDE}✅ Puerto abierto${NC}"
                pausa
                ;;
            2)
                read -p "Puerto a cerrar: " pto
                read -p "Protocolo (tcp/udp/ambos): " proto
                if [ "$proto" = "ambos" ]; then
                    ufw deny "$pto"/tcp
                    ufw deny "$pto"/udp
                    sed -i "/^$pto\/tcp/d" "$ARCH_PUERTOS"
                    sed -i "/^$pto\/udp/d" "$ARCH_PUERTOS"
                else
                    ufw deny "$pto/$proto"
                    sed -i "/^$pto\/$proto/d" "$ARCH_PUERTOS"
                fi
                registrar "Puerto cerrado: $pto ($proto)"
                echo -e "${VERDE}✅ Puerto cerrado${NC}"
                pausa
                ;;
            3)
                echo -e "${CYAN}--- Puertos Abiertos ---${NC}"
                if [ -s "$ARCH_PUERTOS" ]; then
                    cat "$ARCH_PUERTOS"
                else
                    echo "Sin puertos registrados"
                fi
                echo -e "\n--- Puertos activos en el sistema ---"
                netstat -tulpn | grep LISTEN
                pausa
                ;;
            4) break ;;
            *) echo -e "${ROJO}❌ Opción inválida${NC}"; pausa ;;
        esac
    done
}

# ==============================
# GESTIÓN DE IPs
# ==============================
menu_ips() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE DIRECCIONES IP ===${NC}"
        echo "1. Permitir IP"
        echo "2. Bloquear IP"
        echo "3. Ver lista de reglas"
        echo "4. Volver al menú principal"
        read -p "Selecciona una opción: " op

        case $op in
            1)
                read -p "IP a permitir: " ip
                ufw allow from "$ip"
                echo "PERMITIR:$ip" >> "$ARCH_IPS"
                registrar "IP permitida: $ip"
                echo -e "${VERDE}✅ IP permitida${NC}"
                pausa
                ;;
            2)
                read -p "IP a bloquear: " ip
                ufw deny from "$ip"
                echo "BLOQUEAR:$ip" >> "$ARCH_IPS"
                registrar "IP bloqueada: $ip"
                echo -e "${VERDE}✅ IP bloqueada${NC}"
                pausa
                ;;
            3)
                echo -e "${CYAN}--- Reglas de IP ---${NC}"
                if [ -s "$ARCH_IPS" ]; then
                    cat "$ARCH_IPS"
                else
                    echo "Sin reglas definidas"
                fi
                echo -e "\n--- Estado del Firewall ---"
                ufw status numbered
                pausa
                ;;
            4) break ;;
            *) echo -e "${ROJO}❌ Opción inválida${NC}"; pausa ;;
        esac
    done
}

# ==============================
# GESTIÓN DE BANNER
# ==============================
menu_banner() {
    while true; do
        clear
        echo -e "${AZUL}=== GESTIÓN DE BANNER DE BIENVENIDA ===${NC}"
        echo "1. Ver banner actual"
        echo "2. Editar banner"
        echo "3. Restaurar banner predeterminado"
        echo "4. Volver al menú principal"
        read -p "Selecciona una opción: " op

        case $op in
            1)
                echo -e "${CYAN}--- BANNER ACTUAL ---${NC}"
                cat "$ARCH_BANNER"
                pausa
                ;;
            2)
                nano "$ARCH_BANNER"
                registrar "Banner modificado"
                echo -e "${VERDE}✅ Banner actualizado${NC}"
                pausa
                ;;
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
                registrar "Banner restaurado a predeterminado"
                echo -e "${VERDE}✅ Banner restaurado${NC}"
                pausa
                ;;
            4) break ;;
            *) echo -e "${ROJO}❌ Opción inválida${NC}"; pausa ;;
        esac
    done
}

# ==============================
# MENÚ PRINCIPAL
# ==============================
while true; do
    clear
    echo -e "${AZUL}=============================================${NC}"
    echo -e "${AZUL}      MENÚ DE ADMINISTRACIÓN COMPLETO       ${NC}"
    echo -e "${AZUL}=============================================${NC}"
    echo "1. Gestión de Usuarios"
    echo "2. Gestión de Puertos"
    echo "3. Gestión de Direcciones IP"
    echo "4. Gestión de Banner"
    echo "5. Ver registro de actividades"
    echo "6. Salir"
    echo -e "${AZUL}=============================================${NC}"
    read -p "Elige una opción: " main_op

    case $main_op in
        1) menu_usuarios ;;
        2) menu_puertos ;;
        3) menu_ips ;;
        4) menu_banner ;;
        5)
            echo -e "${CYAN}--- REGISTRO DE ACCIONES ---${NC}"
            if [ -s "$LOGS" ]; then
                cat "$LOGS"
            else
                echo "Sin registros aún"
            fi
            pausa
            ;;
        6)
            echo -e "${VERDE}👋 Saliendo del sistema...${NC}"
            exit 0
            ;;
        *)
            echo -e "${ROJO}❌ Opción inválida${NC}"
            pausa
            ;;
    esac
done
EOF

# Dar permiso de ejecución al menú
chmod +x /usr/bin/menu_admin

# Mensaje final
echo -e "${VERDE}=============================================${NC}"
echo -e "${VERDE}✅ INSTALACIÓN FINALIZADA CON ÉXITO ✅${NC}"
echo -e "${VERDE}=============================================${NC}"
echo -e "Para abrir el menú de administración escribe: ${AMARILLO}menu_admin${NC}"
echo -e "${VERDE}=============================================${NC}"
