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

# ================================================================
#   JITTER Bot - Script de inicio con PM2
#   Configura las variables y ejecuta el bot
# ================================================================

echo "=== JITTER Bot Setup ==="
echo ""

# Verificar que existe .env o pedirlos
if [[ ! -f .env ]]; then
    echo -n "BOT_TOKEN (@BotFather): "; read BOT_TOKEN
    echo -n "Tu Telegram ID (@userinfobot): "; read ADMIN_IDS
    echo -n "URL del License Server (ej. https://app.railway.app): "; read LICENSE_SERVER
    echo -n "ADMIN_TOKEN (mismo del servidor): "; read ADMIN_TOKEN

    cat > .env << ENV
BOT_TOKEN=$BOT_TOKEN
ADMIN_IDS=$ADMIN_IDS
LICENSE_SERVER=$LICENSE_SERVER
ADMIN_TOKEN=$ADMIN_TOKEN
ENV
    echo "✓ .env guardado"
fi

# Cargar .env
export $(cat .env | xargs)

# Instalar dependencias si hace falta
[[ ! -d node_modules ]] && npm install

# Iniciar con PM2
pm2 delete netgetk-bot 2>/dev/null
pm2 start bot.js --name netgetk-bot \
    --env production \
    -e /tmp/netgetk-bot-err.log \
    -o /tmp/netgetk-bot-out.log

pm2 save 2>/dev/null
pm2 startup 2>/dev/null

echo ""
echo "✓ Bot iniciado. Ver logs: pm2 logs netgetk-bot"
