#!/bin/bash
# ============================================
#   JITTER SSH MANAGER - EDICIÓN MEJORADA
# ============================================

# Colores mejorados
R="\033[1;31m"
V="\033[1;32m"
A="\033[1;33m"
AZ="\033[1;34m"
M="\033[1;35m"
C="\033[1;36m"
B="\033[1;37m"
GRIS="\033[0;37m"
N="\033[0m"

# Rutas de archivos
DIR_CONF="/etc/JitterVPN"
DB_USUARIOS="$DIR_CONF/usuarios.db"
BANNER_SSH="/etc/ssh/banner.txt"
BANNER_DROPBEAR="/etc/dropbear/banner.txt"

# Verificar root
[ "$EUID" -ne 0 ] && { echo -e "${R}❌ Ejecutá este script como ROOT${N}"; exit 1; }

# Crear carpetas y archivos si no existen
mkdir -p "$DIR_CONF"
touch "$DB_USUARIOS"
mkdir -p /etc/dropbear

# Función pausa estética
pausa(){
  echo -e "\n${GRIS}──────────────────────────────────────────${N}"
  read -p "✨ Presioná ENTER para continuar..."
}

# Función para mostrar encabezado
encabezado(){
  clear
  echo -e "${AZ}╔═════════════════════════════════════════╗${N}"
  echo -e "${AZ}║${N}        ${B}$1${N}        ${AZ}║${N}"
  echo -e "${AZ}╚═════════════════════════════════════════╝${N}"
  echo ""
}

# -------- CONFIGURAR BANNER SSH Y DROPBEAR --------
configurar_banner(){
  encabezado "CONFIGURAR BANNER DE ACCESO"
  echo -e "${C}Escribí el mensaje que quieras mostrar al conectarse (termina con línea vacía):${N}"
  echo -e "${GRIS}-------------------------------------------${N}"

  # Leer texto del banner
  banner_texto=""
  while IFS= read -r line; do
    [ -z "$line" ] && break
    banner_texto+="$line\n"
  done

  # Guardar banner SSH
  echo -e "$banner_texto" > "$BANNER_SSH"
  # Guardar banner Dropbear
  echo -e "$banner_texto" > "$BANNER_DROPBEAR"

  # Activar en configuración SSH
  if ! grep -q "^Banner" /etc/ssh/sshd_config; then
    echo "Banner $BANNER_SSH" >> /etc/ssh/sshd_config
  else
    sed -i "s|^Banner.*|Banner $BANNER_SSH|" /etc/ssh/sshd_config
  fi

  # Activar en Dropbear
  sed -i 's/DROPBEAR_BANNER=.*/DROPBEAR_BANNER="'"$BANNER_DROPBEAR"'"/' /etc/default/dropbear 2>/dev/null

  # Reiniciar servicios
  systemctl restart ssh 2>/dev/null
  systemctl restart dropbear 2>/dev/null

  echo -e "${V}✅ Banner actualizado correctamente para SSH y Dropbear${N}"
  pausa
}

# -------- CAMBIAR PUERTOS SSH --------
cambiar_puertos_ssh(){
  encabezado "CAMBIAR PUERTOS SSH"
  read -p "🔌 Puerto nuevo para SSH (actual: 22): " p_ssh
  read -p "🔌 Puerto nuevo para SSH extra: " p_ssh2

  # Cambiar en sshd_config
  sed -i "s/^Port .*/Port $p_ssh/" /etc/ssh/sshd_config
  grep -q "^Port $p_ssh" /etc/ssh/sshd_config || echo "Port $p_ssh" >> /etc/ssh/sshd_config

  # Agregar segundo puerto
  if grep -q "^ListenAddress" /etc/ssh/sshd_config; then
    echo "Port $p_ssh2" >> /etc/ssh/sshd_config
  else
    sed -i "/^Port $p_ssh/a Port $p_ssh2" /etc/ssh/sshd_config
  fi

  # Permitir en firewall
  ufw allow "$p_ssh"/tcp 2>/dev/null
  ufw allow "$p_ssh2"/tcp 2>/dev/null

  systemctl restart ssh
  echo -e "${V}✅ Puertos SSH cambiados: $p_ssh y $p_ssh2${N}"
  pausa
}

# -------- CREAR USUARIO SSH --------
crear_usuario(){
  encabezado "CREAR NUEVO USUARIO SSH"

  read -p "👤 Nombre de usuario: " user
  read -s -p "🔑 Contraseña: " pass; echo ""
  read -p "📅 Días de duración: " dias
  read -p "🔢 Límite de conexiones simultáneas: " limite

  if id "$user" &>/dev/null; then
    echo -e "${R}❌ El usuario $user ya existe${N}"
    pausa
    return
  fi

  # Calcular fecha de expiración
  exp=$(date -d "+${dias} days" +%Y-%m-%d)
  exp_timestamp=$(date -d "$exp" +%s)
  actual_timestamp=$(date +%s)
  dias_rest=$(( (exp_timestamp - actual_timestamp) / 86400 ))

  # Crear usuario sin carpeta, sin shell
  useradd -M -s /bin/false -e "$exp" "$user"
  echo "$user:$pass" | chpasswd

  # Guardar límite de conexiones
  echo "$user $limite $exp_timestamp" >> "$DB_USUARIOS"

  # Configurar límite de conexiones en PAM
  echo -e "\n# Límite para $user" >> /etc/security/limits.conf
  echo "$user hard maxlogins $limite" >> /etc/security/limits.conf

  # Obtener IP del servidor
  IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

  echo -e "\n${V}✅ USUARIO CREADO EXITOSAMENTE${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"
  echo -e "${B}Usuario      :${N} $user"
  echo -e "${B}Contraseña   :${N} $pass"
  echo -e "${B}Expiración   :${N} $exp (quedan $dias_rest días)"
  echo -e "${B}Límite cone. :${N} $limite"
  echo -e "${B}IP Servidor  :${N} $IP"
  echo -e "${GRIS}──────────────────────────────────────────${N}"
  pausa
}

# -------- ELIMINAR USUARIO --------
eliminar_usuario(){
  encabezado "ELIMINAR USUARIO SSH"
  read -p "👤 Usuario a eliminar: " user

  if id "$user" &>/dev/null; then
    # Matar procesos activos
    pkill -KILL -u "$user" 2>/dev/null
    # Borrar usuario
    userdel -r "$user" 2>/dev/null
    # Borrar de base de datos
    sed -i "/^$user /d" "$DB_USUARIOS" 2>/dev/null
    # Borrar límites
    sed -i "/^$user hard maxlogins/d" /etc/security/limits.conf 2>/dev/null

    echo -e "${V}✅ Usuario $user eliminado completamente${N}"
  else
    echo -e "${R}❌ El usuario no existe${N}"
  fi
  pausa
}

# -------- LISTAR USUARIOS --------
listar_usuarios(){
  encabezado "LISTA DE USUARIOS SSH"

  echo -e "${C}Usuario | Conexiones | Expira | Días restantes${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"

  # Leer usuarios del sistema
  awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd | sort | while read -r u; do
    # Obtener fecha de expiración
    exp_timestamp=$(awk -v u="$u" '$1==u{print $3}' "$DB_USUARIOS")
    limite=$(awk -v u="$u" '$1==u{print $2}' "$DB_USUARIOS")

    if [ -n "$exp_timestamp" ]; then
      exp_fecha=$(date -d "@$exp_timestamp" +%Y-%m-%d)
      actual=$(date +%s)
      dias_rest=$(( (exp_timestamp - actual) / 86400 ))

      if [ "$dias_rest" -lt 0 ]; then
        estado="${R}EXPIRADO${N}"
      else
        estado="${V}$dias_rest días${N}"
      fi

      echo -e "${B}$u${N}    |    ${C}$limite${N}    |    $exp_fecha    |    $estado"
    else
      echo -e "${B}$u${N}    |    ${GRIS}sin dato${N}    |    ${GRIS}desconocido${N}    |    ${GRIS}--${N}"
    fi
  done

  pausa
}

# -------- VER CONEXIONES ACTIVAS --------
ver_conexiones(){
  encabezado "CONEXIONES ACTIVAS AHORA"
  echo -e "${C}Usuario        Origen IP        Puerto${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"
  who | awk '{print $1"        "$5"        "$2}' | sed 's/[()]//g'
  echo -e "\n${C}Total conexiones: $(who | wc -l)${N}"
  pausa
}

# -------- INSTALAR DROPBEAR --------
instalar_dropbear(){
  encabezado "INSTALAR Y CONFIGURAR DROPBEAR"

  read -p "🔌 Puerto principal Dropbear (ej: 444): " p1
  read -p "🔌 Puerto extra Dropbear (ej: 80): " p2

  apt-get update -y &>/dev/null
  apt-get install -y dropbear &>/dev/null

  # Configuración completa
  sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
  sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=$p1/" /etc/default/dropbear
  sed -i "s/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=\"-p $p2 -b $BANNER_DROPBEAR\"/" /etc/default/dropbear

  # Agregar shells válidas
  grep -q "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells
  grep -q "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

  # Permitir en firewall
  ufw allow "$p1"/tcp 2>/dev/null
  ufw allow "$p2"/tcp 2>/dev/null

  systemctl restart dropbear
  systemctl enable dropbear &>/dev/null

  echo -e "${V}✅ Dropbear instalado en puertos: $p1 y $p2${N}"
  echo -e "${V}✅ Banner activado en Dropbear${N}"
  pausa
}

# -------- INSTALAR PROXY PYTHON (WEBSOCKET) --------
instalar_proxy_python(){
  encabezado "INSTALAR PROXY WEBSOCKET PYTHON"

  read -p "🔌 Puerto para el Proxy (ej: 8080): " pport
  apt-get install -y python3 &>/dev/null

  cat > /usr/local/bin/jitter-proxy.py <<'PYEOF'
#!/usr/bin/env python3
import socket, threading, sys, select
LISTENING_ADDR='0.0.0.0'
try: LISTENING_PORT=int(sys.argv[1])
except: LISTENING_PORT=8080
PASS=''
BUFLEN=8196*8
TIMEOUT=60
DEFAULT_HOST='127.0.0.1:22'
RESPONSE='HTTP/1.1 101 JitterVPN-Connected\r\nServer: JitterSSH\r\n\r\n'

class Server(threading.Thread):
    def __init__(self,host,port):
        threading.Thread.__init__(self)
        self.running=False
        self.host=host; self.port=port
        self.threads=[]
        self.threadsLock=threading.Lock()
    def run(self):
        self.soc=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        self.soc.settimeout(2)
        self.soc.bind((self.host,self.port))
        self.soc.listen(100)
        self.running=True
        while self.running:
            try:
                c,addr=self.soc.accept(); c.setblocking(1)
            except socket.timeout: continue
            conn=ConnectionHandler(c,self,addr); conn.start()
            self.addConn(conn)
        self.soc.close()
    def addConn(self,conn):
        with self.threadsLock:
            if self.running: self.threads.append(conn)
    def removeConn(self,conn):
        with self.threadsLock: self.threads.remove(conn)

class ConnectionHandler(threading.Thread):
    def __init__(self,sClient,server,addr):
        threading.Thread.__init__(self)
        self.client=sClient; self.clientClosed=False
        self.targetClosed=True; self.server=server
    def close(self):
        try:
            if not self.clientClosed: self.client.shutdown(socket.SHUT_RDWR); self.client.close()
        except: pass
        self.clientClosed=True
        try:
            if not self.targetClosed: self.target.shutdown(socket.SHUT_RDWR); self.target.close()
        except: pass
        self.targetClosed=True
    def run(self):
        try:
            head=self.client.recv(BUFLEN).decode(errors='ignore')
            hostPort=self.findHeader(head,'X-Real-Host')
            if hostPort=='': hostPort=DEFAULT_HOST
            if hostPort!='':
                passwd=self.findHeader(head,'X-Pass')
                if len(PASS)!=0 and passwd==PASS: self.method_CONNECT(hostPort)
                elif len(PASS)!=0 and passwd!=PASS: self.client.send(b'HTTP/1.1 401 Unauthorized\r\n\r\n')
                elif hostPort.startswith('127.0.0.1') or hostPort.startswith('localhost'): self.method_CONNECT(hostPort)
                else: self.client.send(b'HTTP/1.1 403 Forbidden\r\n\r\n')
            else: self.client.send(b'HTTP/1.1 400 Bad Request\r\n\r\n')
        except Exception as e: pass
        finally: self.close(); self.server.removeConn(self)
    def findHeader(self,head,header):
        aux=head.find(header+': ')
        if aux==-1: return ''
        aux=head.find(':',aux); head=head[aux+2:]
        aux=head.find('\r\n')
        if aux==-1: return ''
        return head[:aux]
    def connect_target(self,host):
        i=host.find(':')
        if i!=-1: port=int(host[i+1:]); host=host[:i]
        else: port=22
        (soc_family,_,_,_,address)=socket.getaddrinfo(host,port)[0]
        self.target=socket.socket(soc_family,socket.SOCK_STREAM); self.targetClosed=False
        self.target.connect(address)
    def method_CONNECT(self,path):
        self.connect_target(path)
        self.client.sendall(RESPONSE.encode())
        self.doCONNECT()
    def doCONNECT(self):
        socs=[self.client,self.target]
        while True:
            (recv,_,err)=select.select(socs,[],socs,TIMEOUT)
            if err: break
            if recv:
                for in_ in recv:
                    try:
                        data=in_.recv(BUFLEN)
                        if data:
                            if in_ is self.target: self.client.send(data)
                            else:
                                while data: sent=self.target.send(data); data=data[sent:]
                        else: return
                    except: return

def main():
    print(f"✅ Proxy corriendo en {LISTENING_ADDR}:{LISTENING_PORT}")
    server=Server(LISTENING_ADDR,LISTENING_PORT); server.start()
    while True:
        try: threading.Event().wait()
        except KeyboardInterrupt: server.running=False; break

if __name__=='__main__': main()
PYEOF

  chmod +x /usr/local/bin/jitter-proxy.py

  # Servicio systemd
  cat > /etc/systemd/system/jitter-proxy.service <<EOF
[Unit]
Description=JitterVPN Proxy WebSocket
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/jitter-proxy.py $pport
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload &>/dev/null
  systemctl enable jitter-proxy &>/dev/null
  systemctl restart jitter-proxy &>/dev/null

  ufw allow "$pport"/tcp 2>/dev/null

  echo -e "${V}✅ Proxy WebSocket activo en puerto: $pport${N}"
  pausa
}

# -------- ESTADO SERVICIOS --------
estado(){
  encabezado "ESTADO DE SERVICIOS"

  for s in ssh dropbear jitter-proxy; do
    if systemctl is-active --quiet $s; then
      echo -e "🔹 $s: ${V}🟢 ACTIVO${N}"
    else
      echo -e "🔹 $s: ${R}🔴 INACTIVO${N}"
    fi
  done

  echo -e "\n${C}Puertos abiertos relevantes:${N}"
  netstat -tulpn 2>/dev/null | grep -E 'ssh|dropbear|python' | awk '{print "   " $4}'

  pausa
}

# -------- MENÚ PRINCIPAL --------
while true; do
  clear
  IP=$(hostname -I | awk '{print $1}')

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
