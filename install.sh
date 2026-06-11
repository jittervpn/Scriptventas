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

# -------- 8. CONFIGURAR BANNER --------
configurar_banner(){
  encabezado "CONFIGURAR BANNER SSH / DROPBEAR"
  echo -e "${C}Escribí el texto del banner (terminá con línea vacía):${N}"
  echo -e "${GRIS}-------------------------------------------${N}"

  texto=""
  while IFS= read -r linea; do [ -z "$linea" ] && break; texto+="$linea\n"; done

  # Guardar banner
  echo -e "$texto" > "$BANNER_SSH"
  echo -e "$texto" > "$BANNER_DROPBEAR"

  # Activar en SSH
  sed -i '/^Banner/d' /etc/ssh/sshd_config
  echo "Banner $BANNER_SSH" >> /etc/ssh/sshd_config

  # Activar en Dropbear
  sed -i 's/^DROPBEAR_BANNER=.*/DROPBEAR_BANNER="'"$BANNER_DROPBEAR"'"/' /etc/default/dropbear 2>/dev/null
  grep -q "DROPBEAR_BANNER" /etc/default/dropbear || echo 'DROPBEAR_BANNER="'"$BANNER_DROPBEAR"'"' >> /etc/default/dropbear

  systemctl restart ssh dropbear 2>/dev/null
  registrar "Banner actualizado"
  echo -e "${V}✅ Banner aplicado correctamente${N}"
  pausa
}

# -------- 9. CAMBIAR PUERTOS SSH --------
cambiar_puertos_ssh(){
  encabezado "CAMBIAR PUERTOS SSH"
  read -p "🔌 Puerto principal SSH: " p1
  read -p "🔌 Puerto secundario SSH: " p2

  sed -i 's/^Port [0-9]*/Port '"$p1"'/' /etc/ssh/sshd_config
  grep -q "^Port $p1" /etc/ssh/sshd_config || echo "Port $p1" >> /etc/ssh/sshd_config
  grep -q "^Port $p2" /etc/ssh/sshd_config || echo "Port $p2" >> /etc/ssh/sshd_config

  # Firewall
  ufw allow "$p1"/tcp "$p2"/tcp 2>/dev/null
  systemctl restart ssh

  registrar "Puertos SSH cambiados: $p1 y $p2"
  echo -e "${V}✅ Puertos actualizados${N}"
  pausa
}

# -------- 1. CREAR USUARIO --------
crear_usuario(){
  encabezado "CREAR USUARIO SSH"
  read -p "👤 Usuario: " user
  read -s -p "🔑 Contraseña: " pass; echo ""
  read -p "📅 Días de duración: " dias
  read -p "🔢 Límite conexiones: " limite

  if id "$user" &>/dev/null; then
    echo -e "${R}❌ Ya existe${N}"; pausa; return
  fi

  exp=$(date -d "+${dias} days" +%Y-%m-%d)
  exp_ts=$(date -d "$exp" +%s)

  useradd -M -s /bin/false -e "$exp" "$user"
  echo "$user:$pass" | chpasswd

  # Guardar datos
  echo "$user $limite $exp_ts" >> "$DB_USUARIOS"

  # Límites
  echo "$user hard maxlogins $limite" >> /etc/security/limits.conf

  IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

  echo -e "\n${V}✅ USUARIO CREADO${N}"
  echo -e "${B}Usuario:${N} $user"
  echo -e "${B}Pass:${N} $pass"
  echo -e "${B}Expira:${N} $exp"
  echo -e "${B}IP:${N} $IP"

  registrar "Usuario creado: $user"
  pausa
}

# -------- 2. ELIMINAR USUARIO --------
eliminar_usuario(){
  encabezado "ELIMINAR USUARIO"
  read -p "👤 Usuario a borrar: " user

  if id "$user" &>/dev/null; then
    pkill -KILL -u "$user" 2>/dev/null
    userdel -r "$user" 2>/dev/null
    sed -i "/^$user /d" "$DB_USUARIOS"
    sed -i "/^$user hard maxlogins/d" /etc/security/limits.conf
    echo -e "${V}✅ Eliminado${N}"
    registrar "Usuario eliminado: $user"
  else
    echo -e "${R}❌ No existe${N}"
  fi
  pausa
}

# -------- 3. LISTAR USUARIOS --------
listar_usuarios(){
  encabezado "LISTA DE USUARIOS"
  echo -e "${C}Usuario | Límite | Expira | Días restantes${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"

  awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd | sort | while read u; do
    datos=$(awk -v u="$u" '$1==u{print $2" "$3}' "$DB_USUARIOS")
    if [ -n "$datos" ]; then
      lim=$(echo "$datos" | awk '{print $1}')
      exp_ts=$(echo "$datos" | awk '{print $2}')
      exp_fmt=$(date -d "@$exp_ts" +%Y-%m-%d)
      act=$(date +%s)
      dias=$(( (exp_ts - act)/86400 ))
      [ "$dias" -lt 0 ] && estado="${R}EXPIRADO${N}" || estado="${V}$dias días${N}"
      echo -e "${B}$u${N} | $lim | $exp_fmt | $estado"
    else
      echo -e "${B}$u${N} | ${GRIS}sin dato${N}"
    fi
  done
  pausa
}

# -------- 7. VER CONEXIONES --------
ver_conexiones(){
  encabezado "CONEXIONES ACTIVAS"
  echo -e "${C}Usuario | Origen | Puerto${N}"
  echo -e "${GRIS}──────────────────────────────────────────${N}"
  who | awk '{print $1" | "$5" | "$2}' | sed 's/[()]//g'
  echo -e "\n${C}Total: $(who | wc -l)${N}"
  pausa
}

# -------- 4. INSTALAR DROPBEAR --------
instalar_dropbear(){
  encabezado "INSTALAR DROPBEAR"
  read -p "🔌 Puerto 1: " p1
  read -p "🔌 Puerto 2: " p2

  apt update -y &>/dev/null
  apt install -y dropbear &>/dev/null

  sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
  sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=$p1/" /etc/default/dropbear
  sed -i "s/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=\"-p $p2 -b $BANNER_DROPBEAR\"/" /etc/default/dropbear

  grep -q "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells

  ufw allow "$p1"/tcp "$p2"/tcp 2>/dev/null
  systemctl restart dropbear
  systemctl enable dropbear &>/dev/null

  echo -e "${V}✅ Dropbear listo en $p1 y $p2${N}"
  registrar "Dropbear instalado"
  pausa
}

# -------- 5. INSTALAR PROXY WS --------
instalar_proxy_python(){
  encabezado "INSTALAR PROXY WEBSOCKET"
  read -p "🔌 Puerto: " pport
  apt install -y python3 &>/dev/null

  cat > /usr/local/bin/jitter-proxy.py <<'PYEOF'
#!/usr/bin/env python3
import socket, threading, sys, select
LISTENING_ADDR='0.0.0.0'
LISTENING_PORT=int(sys.argv[1]) if len(sys.argv)>1 else 8080
PASS=''
BUFLEN=8196*8
TIMEOUT=60
DEFAULT_HOST='127.0.0.1:22'
RESPONSE='HTTP/1.1 101 JitterVPN\r\n\r\n'

class Server(threading.Thread):
    def __init__(self,h,p):
        super().__init__()
        self.h=h; self.p=p; self.running=True
    def run(self):
        s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        s.bind((self.h,self.p)); s.listen(100)
        while self.running:
            c,a=s.accept()
            threading.Thread(target=self.handle,args=(c,)).start()
    def handle(self,c):
        try:
            h=c.recv(8192).decode()
            host=[l for l in h.split('\r\n') if 'X-Real-Host:' in l]
            host=host[0].split(': ',1)[1] if host else DEFAULT_HOST
            ip,prt=host.split(':') if ':' in host else ('127.0.0.1',22)
            t=socket.socket(); t.connect((ip,int(prt)))
            c.send(RESPONSE.encode())
            for _ in range(2):
                threading.Thread(target=self.pipe,args=(c,t)).start()
        except: pass
    def pipe(self,a,b):
        while self.running:
            d=a.recv(8192)
            if not d:break
            b.send(d)

if __name__=='__main__':
    s=Server(LISTENING_ADDR,LISTENING_PORT); s.start()
    print(f"Proxy en {LISTENING_ADDR}:{LISTENING_PORT}")
    while True:input()
PYEOF

  chmod +x /usr/local/bin/jitter-proxy.py

  cat > /etc/systemd/system/jitter-proxy.service <<EOF
[Unit]
Description=Jitter Proxy
After=network.target
[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/jitter-proxy.py $pport
Restart=always
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now jitter-proxy
  ufw allow "$pport"/tcp 2>/dev/null

  echo -e "${V}✅ Proxy activo en $pport${N}"
  registrar "Proxy instalado"
  pausa
}

# -------- 6. ESTADO SERVICIOS --------
estado(){
  encabezado "ESTADO DE SERVICIOS"
  for s in ssh dropbear jitter-proxy; do
    if systemctl is-active --quiet $s; then
      echo -e "🔹 $s: ${V}🟢 ACTIVO${N}"
    else
      echo -e "🔹 $s: ${R}🔴 INACTIVO${N}"
    fi
  done
  echo -e "\n${C}Puertos abiertos:${N}"
  netstat -tulpn 2>/dev/null | grep -E 'ssh|dropbear|python' | awk '{print "   "$4}'
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
