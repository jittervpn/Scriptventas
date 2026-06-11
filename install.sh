#!/bin/bash
# ============================================
#   JITTER SSH MANAGER - VERSIÓN CORREGIDA
# ============================================

# Colores
R="\033[1;31m"
V="\033[1;32m"
A="\033[1;33m"
AZ="\033[1;34m"
M="\033[1;35m"
C="\033[1;36m"
B="\033[1;37m"
GRIS="\033[0;37m"
N="\033[0m"

# Rutas
DIR_CONF="/etc/JitterVPN"
DB_USUARIOS="$DIR_CONF/usuarios.db"
BANNER_SSH="/etc/ssh/banner.txt"
BANNER_DROPBEAR="/etc/dropbear/banner.txt"

# Verificar root
[ "$EUID" -ne 0 ] && { echo -e "${R}❌ Ejecutá como ROOT${N}"; exit 1; }

# Crear carpetas
mkdir -p "$DIR_CONF" /etc/dropbear
touch "$DB_USUARIOS" /var/log/jitter-acciones.log

# Funciones
pausa(){
  echo -e "\n${GRIS}──────────────────────────────────────────${N}"
  read -p "✨ Presioná ENTER para continuar..."
}

encabezado(){
  clear
  echo -e "${AZ}╔═════════════════════════════════════════╗${N}"
  echo -e "${AZ}║${N}        ${B}$1${N}        ${AZ}║${N}"
  echo -e "${AZ}╚═════════════════════════════════════════╝${N}"
  echo ""
}

registrar(){
  echo "[$(date +%d/%m/%Y %H:%M)] $1" >> /var/log/jitter-acciones.log
}

# -------- 8. CONFIGURAR BANNER (CORREGIDO) --------
configurar_banner(){
  encabezado "CONFIGURAR BANNER SSH / DROPBEAR"
  echo -e "${C}Escribí el texto del banner (presioná ENTER dos veces para terminar):${N}"
  echo -e "${GRIS}-------------------------------------------${N}"
  
  # Método corregido para entrada multinea
  texto=""
  while IFS= read -r linea; do
    [ -z "$linea" ] && break
    texto="${texto}${linea}\n"
  done

  # Si no se ingresó nada, usar banner por defecto
  if [ -z "$texto" ]; then
    texto="Bienvenido al servidor JitterVPN\n"
  fi

  # Guardar banner
  echo -e "$texto" > "$BANNER_SSH"
  echo -e "$texto" > "$BANNER_DROPBEAR"

  # Activar en SSH
  sed -i '/^Banner/d' /etc/ssh/sshd_config
  echo "Banner $BANNER_SSH" >> /etc/ssh/sshd_config

  # Activar en Dropbear
  if [ -f /etc/default/dropbear ]; then
    sed -i 's/^DROPBEAR_BANNER=.*/DROPBEAR_BANNER="'"$BANNER_DROPBEAR"'"/' /etc/default/dropbear
    grep -q "DROPBEAR_BANNER" /etc/default/dropbear || echo 'DROPBEAR_BANNER="'"$BANNER_DROPBEAR"'"' >> /etc/default/dropbear
  fi

  systemctl restart ssh 2>/dev/null
  [ -f /etc/default/dropbear ] && systemctl restart dropbear 2>/dev/null
  
  registrar "Banner actualizado"
  echo -e "${V}✅ Banner aplicado correctamente${N}"
  pausa
}

# -------- 9. CAMBIAR PUERTOS SSH (CORREGIDO) --------
cambiar_puertos_ssh(){
  encabezado "CAMBIAR PUERTOS SSH"
  read -p "🔌 Puerto principal SSH: " p1
  read -p "🔌 Puerto secundario SSH: " p2
  
  # Validar puertos
  if ! [[ "$p1" =~ ^[0-9]+$ ]] || ! [[ "$p2" =~ ^[0-9]+$ ]]; then
    echo -e "${R}❌ Los puertos deben ser números${N}"
    pausa
    return
  fi

  # Limpiar puertos existentes
  sed -i '/^Port /d' /etc/ssh/sshd_config
  
  # Agregar nuevos puertos
  echo "Port $p1" >> /etc/ssh/sshd_config
  echo "Port $p2" >> /etc/ssh/sshd_config

  # Firewall (verificar si ufw está instalado)
  if command -v ufw &>/dev/null; then
    ufw allow "$p1"/tcp 2>/dev/null
    ufw allow "$p2"/tcp 2>/dev/null
  fi
  
  systemctl restart ssh

  registrar "Puertos SSH cambiados: $p1 y $p2"
  echo -e "${V}✅ Puertos actualizados${N}"
  pausa
}

# -------- 1. CREAR USUARIO (CORREGIDO) --------
crear_usuario(){
  encabezado "CREAR USUARIO SSH"
  read -p "👤 Usuario: " user
  
  # Validar usuario
  if [[ ! "$user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${R}❌ Usuario inválido (solo letras, números, - y _)${N}"
    pausa
    return
  fi
  
  read -s -p "🔑 Contraseña: " pass; echo ""
  read -p "📅 Días de duración: " dias
  read -p "🔢 Límite conexiones: " limite

  if id "$user" &>/dev/null; then
    echo -e "${R}❌ Ya existe${N}"; pausa; return
  fi

  exp=$(date -d "+${dias} days" +%Y-%m-%d)
  exp_ts=$(date -d "$exp" +%s)

  useradd -M -s /bin/false -e "$exp" "$user"
  
  # Seguridad: usar chpasswd desde stdin
  echo "$user:$pass" | chpasswd

  # Guardar datos (escapar correctamente)
  echo "$user $limite $exp_ts" >> "$DB_USUARIOS"

  # Límites
  echo "$user hard maxlogins $limite" >> /etc/security/limits.conf

  IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')

  echo -e "\n${V}✅ USUARIO CREADO${N}"
  echo -e "${B}Usuario:${N} $user"
  echo -e "${B}Pass:${N} $pass"
  echo -e "${B}Expira:${N} $exp"
  echo -e "${B}IP:${N} $IP"

  registrar "Usuario creado: $user"
  pausa
}

# -------- 2. ELIMINAR USUARIO (CORREGIDO) --------
eliminar_usuario(){
  encabezado "ELIMINAR USUARIO"
  read -p "👤 Usuario a borrar: " user

  if id "$user" &>/dev/null; then
    # Matar todos los procesos del usuario
    pkill -KILL -u "$user" 2>/dev/null
    userdel -r "$user" 2>/dev/null
    
    # Limpiar archivos de datos
    sed -i "/^$user /d" "$DB_USUARIOS"
    sed -i "/^$user hard maxlogins/d" /etc/security/limits.conf
    
    echo -e "${V}✅ Eliminado${N}"
    registrar "Usuario eliminado: $user"
  else
    echo -e "${R}❌ No existe${N}"
  fi
  pausa
}

# -------- 3. LISTAR USUARIOS (CORREGIDO) --------
listar_usuarios(){
  encabezado "LISTA DE USUARIOS"
  echo -e "${C}Usuario | Límite | Expira | Días restantes${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"

  # Mostrar solo usuarios creados por el script (con shell /bin/false)
  grep -E "/bin/false$" /etc/passwd | cut -d: -f1 | sort | while read -r u; do
    datos=$(awk -v u="$u" '$1==u{print $2" "$3}' "$DB_USUARIOS")
    if [ -n "$datos" ]; then
      lim=$(echo "$datos" | awk '{print $1}')
      exp_ts=$(echo "$datos" | awk '{print $2}')
      exp_fmt=$(date -d "@$exp_ts" +%Y-%m-%d 2>/dev/null || echo "inválido")
      act=$(date +%s)
      dias=$(( (exp_ts - act)/86400 ))
      
      if [ "$dias" -lt 0 ]; then
        estado="${R}EXPIRADO${N}"
      else
        estado="${V}$dias días${N}"
      fi
      echo -e "${B}$u${N} | $lim | $exp_fmt | $estado"
    else
      echo -e "${B}$u${N} | ${GRIS}sin límite${N} | ${GRIS}sin expiración${N} | ${GRIS}---${N}"
    fi
  done
  
  # Mostrar total
  total=$(grep -c "/bin/false$" /etc/passwd)
  echo -e "\n${C}Total de usuarios SSH: $total${N}"
  pausa
}

# -------- 7. VER CONEXIONES (CORREGIDO) --------
ver_conexiones(){
  encabezado "CONEXIONES ACTIVAS"
  
  if ! command -v who &>/dev/null; then
    echo -e "${R}❌ Comando 'who' no disponible${N}"
    pausa
    return
  fi
  
  echo -e "${C}Usuario | Origen | Puerto | Conexión${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"
  
  who | while read -r line; do
    user=$(echo "$line" | awk '{print $1}')
    terminal=$(echo "$line" | awk '{print $2}')
    origen=$(echo "$line" | awk '{print $5}' | sed 's/[()]//g')
    echo -e "${B}$user${N} | ${origen:-local} | $terminal"
  done
  
  total=$(who | wc -l)
  echo -e "\n${C}Total de conexiones activas: $total${N}"
  pausa
}

# -------- 4. INSTALAR DROPBEAR (CORREGIDO) --------
instalar_dropbear(){
  encabezado "INSTALAR DROPBEAR"
  read -p "🔌 Puerto 1: " p1
  read -p "🔌 Puerto 2: " p2

  # Verificar que los puertos sean válidos
  if ! [[ "$p1" =~ ^[0-9]+$ ]] || ! [[ "$p2" =~ ^[0-9]+$ ]]; then
    echo -e "${R}❌ Puertos inválidos${N}"
    pausa
    return
  fi

  apt update -y &>/dev/null
  apt install -y dropbear &>/dev/null

  # Configurar Dropbear
  cat > /etc/default/dropbear <<EOF
NO_START=0
DROPBEAR_PORT=$p1
DROPBEAR_EXTRA_ARGS="-p $p2 -b $BANNER_DROPBEAR"
DROPBEAR_BANNER="$BANNER_DROPBEAR"
EOF

  # Asegurar que /bin/false está en shells
  grep -q "^/bin/false$" /etc/shells || echo "/bin/false" >> /etc/shells

  # Firewall
  if command -v ufw &>/dev/null; then
    ufw allow "$p1"/tcp 2>/dev/null
    ufw allow "$p2"/tcp 2>/dev/null
  fi
  
  systemctl restart dropbear
  systemctl enable dropbear &>/dev/null

  echo -e "${V}✅ Dropbear listo en $p1 y $p2${N}"
  registrar "Dropbear instalado"
  pausa
}

# -------- 5. INSTALAR PROXY WS (CORREGIDO) --------
instalar_proxy_python(){
  encabezado "INSTALAR PROXY WEBSOCKET"
  read -p "🔌 Puerto: " pport
  
  if ! [[ "$pport" =~ ^[0-9]+$ ]] || [ "$pport" -lt 1 ] || [ "$pport" -gt 65535 ]; then
    echo -e "${R}❌ Puerto inválido (1-65535)${N}"
    pausa
    return
  fi
  
  apt install -y python3 &>/dev/null

  cat > /usr/local/bin/jitter-proxy.py <<'PYEOF'
#!/usr/bin/env python3
import socket
import threading
import sys
import select

LISTENING_ADDR = '0.0.0.0'
LISTENING_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
BUFLEN = 8192 * 8
TIMEOUT = 60
DEFAULT_HOST = '127.0.0.1:22'
RESPONSE = b'HTTP/1.1 101 Switching Protocols\r\n\r\n'

class ProxyServer(threading.Thread):
    def __init__(self, host, port):
        super().__init__()
        self.host = host
        self.port = port
        self.running = True
        self.daemon = True
        
    def run(self):
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind((self.host, self.port))
        server_socket.listen(100)
        
        while self.running:
            try:
                client_socket, address = server_socket.accept()
                client_thread = threading.Thread(target=self.handle_client, args=(client_socket,))
                client_thread.daemon = True
                client_thread.start()
            except:
                pass
                
    def handle_client(self, client_socket):
        try:
            data = client_socket.recv(BUFLEN).decode('utf-8', errors='ignore')
            if not data:
                return
                
            # Extraer host objetivo
            target_host = DEFAULT_HOST
            for line in data.split('\r\n'):
                if line.lower().startswith('x-real-host:'):
                    target_host = line.split(':', 1)[1].strip()
                    break
                    
            host, port = target_host.split(':') if ':' in target_host else ('127.0.0.1', '22')
            port = int(port)
            
            # Conectar al destino
            remote_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            remote_socket.settimeout(TIMEOUT)
            remote_socket.connect((host, port))
            
            # Enviar respuesta de upgrade
            client_socket.send(RESPONSE)
            
            # Iniciar transferencia bidireccional
            threading.Thread(target=self.forward_data, args=(client_socket, remote_socket)).start()
            threading.Thread(target=self.forward_data, args=(remote_socket, client_socket)).start()
            
        except Exception as e:
            pass
            
    def forward_data(self, source, destination):
        try:
            while self.running:
                data = source.recv(BUFLEN)
                if not data:
                    break
                destination.send(data)
        except:
            pass
        finally:
            try:
                source.close()
                destination.close()
            except:
                pass

if __name__ == '__main__':
    server = ProxyServer(LISTENING_ADDR, LISTENING_PORT)
    server.start()
    print(f"Proxy WebSocket iniciado en {LISTENING_ADDR}:{LISTENING_PORT}")
    
    try:
        while True:
            input()
    except KeyboardInterrupt:
        server.running = False
        sys.exit(0)
PYEOF

  chmod +x /usr/local/bin/jitter-proxy.py

  cat > /etc/systemd/system/jitter-proxy.service <<EOF
[Unit]
Description=Jitter WebSocket Proxy
After=network.target
Documentation=https://github.com/JitterVPN

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/jitter-proxy.py $pport
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now jitter-proxy
  
  if command -v ufw &>/dev/null; then
    ufw allow "$pport"/tcp 2>/dev/null
  fi

  echo -e "${V}✅ Proxy WebSocket activo en puerto $pport${N}"
  registrar "Proxy WebSocket instalado en puerto $pport"
  pausa
}

# -------- 6. ESTADO SERVICIOS (CORREGIDO) --------
estado(){
  encabezado "ESTADO DE SERVICIOS"
  
  # Servicios a verificar
  services=("ssh" "dropbear" "jitter-proxy")
  
  for s in "${services[@]}"; do
    if systemctl is-active --quiet "$s" 2>/dev/null; then
      echo -e "🔹 $s: ${V}🟢 ACTIVO${N}"
    elif [ "$s" = "jitter-proxy" ] && [ -f /etc/systemd/system/jitter-proxy.service ]; then
      echo -e "🔹 $s: ${R}🔴 INACTIVO (usar 'systemctl start jitter-proxy')${N}"
    elif [ "$s" = "dropbear" ] && [ ! -f /etc/default/dropbear ]; then
      echo -e "🔹 $s: ${GRIS}⚪ NO INSTALADO${N}"
    else
      echo -e "🔹 $s: ${R}🔴 INACTIVO${N}"
    fi
  done
  
  echo -e "\n${C}Puertos SSH activos:${N}"
  grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print "   📡 Puerto "$2}' || echo "   No configurado"
  
  if [ -f /etc/default/dropbear ]; then
    echo -e "\n${C}Puertos Dropbear activos:${N}"
    grep -E "DROPBEAR_PORT|DROPBEAR_EXTRA_ARGS" /etc/default/dropbear 2>/dev/null | grep -oP '[0-9]+' | while read -r port; do
      echo "   📡 Puerto $port"
    done
  fi
  
  pausa
}

# -------- MENÚ PRINCIPAL --------
while true; do
  clear
  
  # Obtener IP de manera segura
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$IP" ] && IP="No disponible"

  echo -e "${AZ}╔═════════════════════════════════════════════════╗${N}"
  echo -e "${AZ}║${N}           🚀  JITTER SSH MANAGER  🚀           ${AZ}║${N}"
  echo -e "${AZ}╠═════════════════════════════════════════════════╣${N}"
  echo -e "${AZ}║${N}  🌐 IP SERVIDOR: ${B}$IP${N}              ${AZ}║${N}"
  echo -e "${AZ}╠═════════════════════════════════════════════════╣${N}"
  echo -e "${AZ}║${N}  ${V}👤 USUARIOS${N}                                          ${AZ}║${N}"
  echo -e "${AZ}║${N}   ${V}1)${N} Crear usuario        ${V}2)${N} Eliminar usuario       ${AZ}║${N}"
  echo -e "${AZ}║${N}   ${V}3)${N} Listar usuarios       ${V}7)${N} Ver conexiones activas  ${AZ}║${N}"
  echo -e "${AZ}╠═════════════════════════════════════════════════╣${N}"
  echo -e "${AZ}║${N}  ${C}⚙️ SERVICIOS${N}                                          ${AZ}║${N}"
  echo -e "${AZ}║${N}   ${C}4)${N} Instalar Dropbear     ${C}5)${N} Instalar Proxy WS       ${AZ}║${N}"
  echo -e "${AZ}║${N}   ${C}6)${N} Estado de servicios                           ${AZ}║${N}"
  echo -e "${AZ}╠═════════════════════════════════════════════════╣${N}"
  echo -e "${AZ}║${N}  ${M}🎨 PERSONALIZACIÓN${N}                                    ${AZ}║${N}"
  echo -e "${AZ}║${N}   ${M}8)${N} Configurar Banner SSH/Dropbear                 ${AZ}║${N}"
  echo -e "${AZ}║${N}   ${M}9)${N} Cambiar puertos SSH                            ${AZ}║${N}"
  echo -e "${AZ}╠═════════════════════════════════════════════════╣${N}"
  echo -e "${AZ}║${N}   ${R}0)${N} 🚪 SALIR DEL SISTEMA                           ${AZ}║${N}"
  echo -e "${AZ}╚═════════════════════════════════════════════════╝${N}"
  echo ""
  read -p "👉 Elegí una opción: " op

  case $op in
    1) crear_usuario ;;
    2) eliminar_usuario ;;
    3) listar_usuarios ;;
    4) instalar_dropbear ;;
    5) instalar_proxy_python ;;
    6) estado ;;
    7) ver_conexiones ;;
    8) configurar_banner ;;
    9) cambiar_puertos_ssh ;;
    0) clear; echo -e "${V}👋 Hasta luego!${N}"; exit 0 ;;
    *) echo -e "${R}❌ Opción inválida${N}"; sleep 1 ;;
  esac
done
