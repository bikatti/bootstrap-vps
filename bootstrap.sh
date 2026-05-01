#!/bin/bash
# ============================================================
#  bootstrap.sh — Configuración automática de VPS
#  Repo: https://github.com/bikatti/bootstrap-vps
#  Uso: curl -fsSL https://raw.githubusercontent.com/bikatti/bootstrap-vps/main/bootstrap.sh | bash
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

NEW_USER="${NEW_USER:-powerranger}"
GITHUB_RAW="https://raw.githubusercontent.com/bikatti/bootstrap-vps/main"

echo ""
echo "╭──────────────────────────────────────────╮"
echo "│        🚀 Bootstrap VPS — Inicio         │"
echo "╰──────────────────────────────────────────╯"
echo ""

read -rp "  🌐 Dominio para n8n (ej: n8n.tudominio.com): " N8N_DOMAIN
read -rp "  📧 Email para SSL (certbot): " SSL_EMAIL

[ -z "$N8N_DOMAIN" ] && error "El dominio es obligatorio."
[ -z "$SSL_EMAIL" ]  && error "El email es obligatorio."

echo ""
echo "  Dominio : $N8N_DOMAIN"
echo "  Email   : $SSL_EMAIL"
echo ""

# 1. ACTUALIZAR SISTEMA
info "Actualizando el sistema..."
apt update -qq && apt upgrade -y -qq
success "Sistema actualizado"

# 2. PAQUETES ESENCIALES
info "Instalando paquetes esenciales..."
apt install -y -qq \
  curl wget git vim htop \
  tmux screen byobu \
  zsh \
  ufw fail2ban \
  certbot python3-certbot-nginx \
  rsync net-tools unzip zip jq \
  build-essential software-properties-common \
  ca-certificates gnupg lsb-release
success "Paquetes instalados"

# 3. DOCKER
if ! command -v docker &>/dev/null; then
  info "Instalando Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt update -qq
  apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker && systemctl start docker
  success "Docker instalado"
else
  warn "Docker ya está instalado, saltando..."
fi

# 4. NGINX
if ! command -v nginx &>/dev/null; then
  info "Instalando Nginx..."
  apt install -y -qq nginx
  systemctl enable nginx && systemctl start nginx
  success "Nginx instalado"
else
  warn "Nginx ya está instalado, saltando..."
fi

# 5. FIREWALL
info "Configurando firewall UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
success "Firewall configurado"

# 6. FAIL2BAN
info "Configurando fail2ban..."
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
systemctl enable fail2ban && systemctl restart fail2ban
success "Fail2ban configurado"

# 7. USUARIO
if ! id "$NEW_USER" &>/dev/null; then
  info "Creando usuario $NEW_USER..."
  useradd -m -s /bin/zsh "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
  usermod -aG docker "$NEW_USER"
  success "Usuario $NEW_USER creado"
else
  warn "Usuario $NEW_USER ya existe, actualizando grupos..."
  usermod -aG sudo "$NEW_USER"
  usermod -aG docker "$NEW_USER"
fi

# 8. ZSH + OH MY ZSH + POWERLEVEL10K
setup_zsh() {
  local TARGET_USER="$1"
  local TARGET_HOME
  TARGET_HOME=$(eval echo "~$TARGET_USER")

  info "Configurando Zsh para $TARGET_USER..."

  if [ ! -d "$TARGET_HOME/.oh-my-zsh" ]; then
    env ZSH="$TARGET_HOME/.oh-my-zsh" HOME="$TARGET_HOME" \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended --keep-zshrc 2>/dev/null || true
  else
    warn "Oh My Zsh ya instalado para $TARGET_USER"
  fi

  P10K_DIR="$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [ ! -d "$P10K_DIR" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    chown -R "$TARGET_USER:$TARGET_USER" "$P10K_DIR"
  fi

  ZSH_PLUGINS_DIR="$TARGET_HOME/.oh-my-zsh/custom/plugins"
  mkdir -p "$ZSH_PLUGINS_DIR"

  if [ ! -d "$ZSH_PLUGINS_DIR/zsh-autosuggestions" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
      "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
    chown -R "$TARGET_USER:$TARGET_USER" "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
  fi

  if [ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]; then
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
      "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
    chown -R "$TARGET_USER:$TARGET_USER" "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
  fi

  cat > "$TARGET_HOME/.zshrc" <<'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  docker
  zsh-autosuggestions
  zsh-syntax-highlighting
  tmux
  sudo
  z
)

source $ZSH/oh-my-zsh.sh

alias ll='ls -lah'
alias gs='git status'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias nginx-reload='sudo systemctl reload nginx'

HISTSIZE=10000
SAVEHIST=10000

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHRC

  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"
  curl -fsSL "$GITHUB_RAW/.p10k.zsh" -o "$TARGET_HOME/.p10k.zsh"
  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.p10k.zsh"
  chsh -s /bin/zsh "$TARGET_USER"
  success "Zsh configurado para $TARGET_USER"
}

setup_zsh root
setup_zsh "$NEW_USER"

# 9. TMUX
info "Configurando tmux..."
cat > /root/.tmux.conf <<'TMUXCONF'
set -g prefix C-a
unbind C-b
bind C-a send-prefix
set -g mouse on
bind | split-window -h
bind - split-window -v
set -g default-terminal "screen-256color"
set -g status-bg colour235
set -g status-fg colour136
set -g status-left '#[fg=colour166]#H '
set -g status-right '#[fg=colour136]%d/%m %H:%M'
TMUXCONF
cp /root/.tmux.conf "/home/$NEW_USER/.tmux.conf"
chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.tmux.conf"
success "Tmux configurado"

# 10. NGINX PARA N8N
info "Configurando Nginx para $N8N_DOMAIN..."
cat > /etc/nginx/sites-available/n8n <<NGINXCONF
server {
    listen 80;
    server_name $N8N_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXCONF
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/n8n
nginx -t && systemctl reload nginx
success "Nginx configurado"

# 11. SSL
info "Generando SSL para $N8N_DOMAIN..."
certbot --nginx -d "$N8N_DOMAIN" --non-interactive --agree-tos -m "$SSL_EMAIL"
success "SSL configurado"

# 12. N8N
info "Instalando n8n..."
if docker ps -a --format '{{.Names}}' | grep -q "^n8n$"; then
  warn "Contenedor n8n ya existe, recreando..."
  docker stop n8n && docker rm n8n
fi

docker run -d \
  --name n8n \
  --restart unless-stopped \
  -p 127.0.0.1:5678:5678 \
  -e N8N_HOST="$N8N_DOMAIN" \
  -e N8N_PROTOCOL=https \
  -e WEBHOOK_URL="https://$N8N_DOMAIN/" \
  -v n8n_data:/home/node/.n8n \
  n8nio/n8n
success "n8n instalado"

echo ""
echo "╭──────────────────────────────────────────╮"
echo "│     ✅  Bootstrap completado             │"
echo "╰──────────────────────────────────────────╯"
echo ""
echo "  🌐 n8n en: https://$N8N_DOMAIN"
echo "  🔑 Contraseña: passwd $NEW_USER"
echo ""
