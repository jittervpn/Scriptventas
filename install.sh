#!/bin/bash
# ============================================
# JITTER SSH MANAGER
# ============================================

# Colores
R="\033[1;31m"; V="\033[1;32m"; A="\033[1;33m"; AZ="\033[1;34m"; M="\033[1;35m"; C="\033[1;36m"; B="\033[1;37m"; N="\033[0m"

[ "$EUID" -ne 0 ] && { echo -e "${R}Ejecutá como root${N}"; exit 1; }

pausa(){ echo ""; read -p "Presioná ENTER para continuar..."; }

# -------- INSTALAR BANNER DE LOGIN --------
instalar_banner_login(){
  cat > /etc/jitter-banner.sh <<'EOF'
#!/bin/bash
# Banner que muestra días restantes al conectar
R="\033[1;31m"; V="\033[1;32m"; A="\033[1;33m"; M="\033[1;35m"; C="\033[1;36m"; B="\033[1;37m"; N="\033[0m"

USER=$(whoami)
# Solo mostrar para usuarios normales, no root
[[ "$USER" == "root" ]] && exit 0
[[ "$UID" -lt 1000 ]] && exit 0

EXP=$(chage -l "$USER" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)

if [[ "$EXP" == "never" ]] || [[ -z "$EXP" ]]; then
    DIAS="Ilimitado"
    COLOR="$V"
else
    EXP_SEC=$(date -d "$EXP" +%s 2>/dev/null)
    HOY_SEC=$(date +%s)
    DIAS=$(( ($EXP_SEC - $HOY_SEC) / 86400 ))

    if [[ $DIAS -lt 0 ]]; then
        COLOR="$R"; DIAS="EXPIRADO"
    elif [[ $DIAS -lt 3 ]]; then
        COLOR="$R"
    elif [[ $DIAS -lt 7 ]]; then
        COLOR="$A"
    else
        COLOR="$V"
    fi
fi

echo -e "${M}╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${M}║${N} ${C}🚀 BIENVENIDO A JITTER VPN 🚀${N} ${M}║${N}"
echo -e "${M}╠══════════════════════════════════════════════════════════╣${N}"
echo -e "${M}║${N} ${B}Usuario:${N} ${C}$USER${N} ${M}║${N}"
echo -e "${M}║${N} ${B}Expira:${N} ${C}${EXP:-Sin fecha}${N} ${M}║${N}"
echo -e "${M}║${N} ${B}Días restantes:${N} ${COLOR}$DIAS${N} ${M}║${N}"
echo -e "${M}╚══════════════════════════════════════════════════════════╝${N}"
echo ""
EOF
  chmod +x /etc/jitter-banner.sh

  # Agregar a /etc/profile si no existe
  grep -q "jitter-banner.sh" /etc/profile || echo "/etc/jitter-banner.sh" >> /etc/profile
}

# -------- CREAR USUARIO SSH --------
crear_usuario(){
  clear
  echo -e "${A}===== CREAR USUARIO SSH =====${N}"
  read -p "Usuario: " user
  read -p "Contraseña: " pass
  read -p "Días de duración: " dias
  read -p "Límite de conexiones: " limite

  if id "$user" &>/dev/null; then
    echo -e "${R}El usuario ya existe${N}"; pausa; return
  fi

  exp=$(date -d "+${dias} days" +%Y-%m-%d)
  useradd -M -s /bin/false -e "$exp" "$user"
  echo "$user:$pass" | chpasswd

  mkdir -p /etc/JitterVPN
  echo "$user $limite" >> /etc/JitterVPN/usuarios.db

  # Instalar banner automático
  instalar_banner_login

  IP=$(curl -4 -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  echo ""
  echo -e "${V}✅ Usuario creado${N}"
  echo -e "${B}Usuario:${N} $user"
  echo -e "${B}Pass:${N} $pass"
  echo -e "${B}Expira:${N} $exp"
  echo -e "${B}Límite:${N} $limite"
  echo -e "${B}IP:${N} $IP"
  echo -e "${A}⚠ El usuario verá su banner con días restantes al conectar${N}"
  pausa
}

# -------- ELIMINAR USUARIO --------
eliminar_usuario(){
  clear
  echo -e "${A}===== ELIMINAR USUARIO =====${N}"
  read -p "Usuario a eliminar: " user
  if id "$user" &>/dev/null; then
    pkill -KILL -u "$user" 2>/dev/null
    userdel -r "$user" 2>/dev/null
    sed -i "/^$user /d" /etc/JitterVPN/usuarios.db 2>/dev/null
    echo -e "${V}✅ Usuario $user eliminado${N}"
  else
    echo -e "${R}No existe${N}"
  fi
  pausa
}

# -------- LISTAR USUARIOS --------
listar_usuarios(){
  clear
  echo -e "${A}===== USUARIOS SSH =====${N}"
  printf "${B}%-15s %-15s %-10s${N}\n" "USUARIO" "EXPIRA" "DÍAS"
  echo -e "${M}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
  awk -F: '$3>=1000 && $1!="nobody"{print $1}' /etc/passwd | while read u; do
    exp=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
    if [[ "$exp" == "never" ]] || [[ -z "$exp" ]]; then
        dias="∞"
        color="$V"
    else
        exp_sec=$(date -d "$exp" +%s 2>/dev/null)
        hoy_sec=$(date +%s)
        dias=$(( ($exp_sec - $hoy_sec) / 86400 ))
        [[ $dias -lt 0 ]] && color="$R" || [[ $dias -lt 3 ]] && color="$R" || [[ $dias -lt 7 ]] && color="$A" || color="$V"
    fi
    printf "${B}%-15s${N} %-15s ${color}%-10s${N}\n" "$u" "${exp:-Nunca}" "$dias"
  done
  pausa
}

# -------- INSTALAR DROPBEAR --------
instalar_dropbear(){
  clear
  echo -e "${A}===== INSTALAR DROPBEAR =====${N}"
  read -p "Puerto Dropbear (ej 444): " p1
  read -p "Puerto Dropbear extra (ej 80): " p2
  apt-get update -y
  apt-get install -y dropbear
  sed -i 's/NO_START=1/NO_START=0/' /etc/default/dropbear
  sed -i "s/DROPBEAR_PORT=.*/DROPBEAR_PORT=$p1/" /etc/default/dropbear
  sed -i "s/DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS=\"-p $p2\"/" /etc/default/dropbear
  grep -q "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells
  grep -q "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells
  instalar_banner_login
  systemctl restart dropbear
  systemctl enable dropbear
  echo -e "${V}✅ Dropbear instalado en puertos $p1 y $p2${N}"
  echo -e "${A}⚠ Banner de días restantes activado${N}"
  pausa
}

# -------- INSTALAR PROXY PYTHON (WEBSOCKET) --------
instalar_proxy_python(){
  clear
  echo -e "${A}===== INSTALAR PROXY PYTHON =====${N}"
  read -p "Puerto del proxy (ej 8080): " pport
  apt-get install -y python3

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
RESPONSE='HTTP/1.1 101 <b>JitterVPN</b>\r\n\r\n'

class Server(threading.Thread):
    def __init__(self,host,port):
        threading.Thread.__init__(self)
        self.running=False
        self.host=host; self.port=port
        self.threads=[]
        self.threadsLock=threading.Lock()
        self.logLock=threading.Lock()
    def run(self):
        self.soc=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        self.soc.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        self.soc.settimeout(2)
        self.soc.bind((self.host,self.port))
        self.soc.listen(0)
        self.running=True
        while self.running:
            try:
                c,addrPara que al usuario le salga un banner con días restantes cuando se conecta por SSH/VPN, tenés que usar el `Banner` de SSH y un script PAM. Lo armé para tu bin:

**1. Agregá estas 2 funciones nuevas a tu script:**

Pegá esto arriba del `# -------- MENÚ PRINCIPAL --------`

```bash
# -------- BANNER CONEXIÓN CON DÍAS RESTANTES --------
configurar_banner_conexion(){
  # Crear script que se ejecuta en cada login SSH
  cat > /etc/ssh/jitter-banner.sh <<'BANEOF'
#!/bin/bash
user=$(whoami)
exp=$(chage -l "$user" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)

if [[ "$exp" == "never" ]] || [[ -z "$exp" ]]; then
    dias="∞"
    echo -e "\033[1;35m╔══════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;37m 🚀 BIENVENIDO A JITTER VPN 🚀 \033[0m \033[1;35m║\033[0m"
    echo -e "\033[1;35m╠══════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;33m Usuario:\033[0m \033[1;36m$user\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;33m Expira:\033[0m \033[1;32mNunca\033[0m"
    echo -e "\033[1;35m╚══════════════════════════════════════════════════════════╝\033[0m"
else
    exp_seg=$(date -d "$exp" +%s 2>/dev/null)
    hoy_seg=$(date +%s)
    dias=$(( ($exp_seg - $hoy_seg) / 86400 ))

    if [ $dias -lt 0 ]; then
        echo -e "\033[1;31m╔══════════════════════════════════════════════════════════╗\033[0m"
        echo -e "\033[1;31m║\033[0m \033[1;37m ⚠ CUENTA VENCIDA ⚠ \033[0m \033[1;31m║\033[0m"
        echo -e "\033[1;31m║\033[0m \033[1;37m Contacta a @JitterVPN para renovar \033[0m \033[1;31m║\033[0m"
        echo -e "\033[1;31m╚══════════════════════════════════════════════════════════╝\033[0m"
        sleep 2
        exit 1
    elif [ $dias -le 3 ]; then
        color="\033[1;31m" # Rojo si quedan 3 días o menos
    elif [ $dias -le 7 ]; then
        color="\033[1;33m" # Amarillo si quedan 7 días o menos
    else
        color="\033[1;32m" # Verde
    fi

    echo -e "\033[1;35m╔══════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;37m 🚀 JITTER VPN - BIENVENIDO 🚀 \033[0m \033[1;35m║\033[0m"
    echo -e "\033[1;35m╠══════════════════════════════════════════════════════════╣\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;33m Usuario:\033[0m \033[1;36m$user\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;33m Expira:\033[0m \033[1;36m$exp\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;33m Días restantes:\033[0m ${color}$dias días\033[0m"
    echo -e "\033[1;35m║\033[0m \033[1;33m Soporte:\033[0m \033[1;36m@JitterVPN\033[0m"
    echo -e "\033[1;35m╚══════════════════════════════════════════════════════════╝\033[0m"
fi
echo ""
BANEOF

  chmod +x /etc/ssh/jitter-banner.sh

  # Activar banner en SSH
  grep -q "/etc/ssh/jitter-banner.sh" /etc/ssh/sshd_config || echo "Banner /etc/ssh/jitter-banner.sh" >> /etc/ssh/sshd_config

  # Usar PAM para mostrar el banner después del login
  grep -q "pam_exec.so" /etc/pam.d/sshd || echo "session optional pam_exec.so stdout /etc/ssh/jitter-banner.sh" >> /etc/pam.d/sshd

  systemctl restart sshd
  echo -e "${V}✓ Banner de conexión activado${N}"
  echo -e "${A}Ahora cuando un usuario se conecte por SSH verá días restantes${N}"
  pausa
}

# -------- DESACTIVAR BANNER CONEXIÓN --------
desactivar_banner_conexion(){
  sed -i '/jitter-banner.sh/d' /etc/ssh/sshd_config
  sed -i '/jitter-banner.sh/d' /etc/pam.d/sshd
  rm -f /etc/ssh/jitter-banner.sh
  systemctl restart sshd
  echo -e "${V}✓ Banner de conexión desactivado${N}"
  pausa
}
