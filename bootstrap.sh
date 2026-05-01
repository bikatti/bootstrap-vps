#!/bin/bash
# ============================================================
#  bootstrap.sh — Configuración automática de VPS
#  Basado en: vmi3076566 (powerranger)
#  Uso: curl -fsSL <URL> | bash
#       o: bash bootstrap.sh
# ============================================================

set -e  # Para si algo falla

# --- Colores para los mensajes ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Variables configurables ---
NEW_USER="${NEW_USER:-powerranger}"      # Usuario a crear (puedes cambiarlo)
INSTALL_N8N="${INSTALL_N8N:-false}"      # Poner "true" para instalar n8n

# ============================================================
echo ""
echo "╭──────────────────────────────────────────╮"
echo "│        🚀 Bootstrap VPS — Inicio         │"
echo "╰──────────────────────────────────────────╯"
echo ""

# ============================================================
# 1. ACTUALIZAR SISTEMA
# ============================================================
info "Actualizando el sistema..."
apt update -qq && apt upgrade -y -qq
success "Sistema actualizado"

# ============================================================
# 2. PAQUETES ESENCIALES
# ============================================================
info "Instalando paquetes esenciales..."
apt install -y -qq \
  curl wget git vim htop \
  tmux screen byobu \
  zsh \
  ufw fail2ban \
  certbot \
  rsync \
  net-tools \
  unzip zip \
  jq \
  build-essential \
  software-properties-common \
  ca-certificates \
  gnupg \
  lsb-release
success "Paquetes instalados"

# ============================================================
# 3. DOCKER
# ============================================================
if ! command -v docker &>/dev/null; then
  info "Instalando Docker..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt update -qq
  apt install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  success "Docker instalado"
else
  warn "Docker ya está instalado, saltando..."
fi

# ============================================================
# 4. NGINX
# ============================================================
if ! command -v nginx &>/dev/null; then
  info "Instalando Nginx..."
  apt install -y -qq nginx
  systemctl enable nginx
  systemctl start nginx
  success "Nginx instalado"
else
  warn "Nginx ya está instalado, saltando..."
fi

# ============================================================
# 5. FIREWALL (UFW)
# ============================================================
info "Configurando firewall UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
success "Firewall configurado (SSH, 80, 443 abiertos)"

# ============================================================
# 6. FAIL2BAN
# ============================================================
info "Configurando fail2ban..."
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2ban configurado"

# ============================================================
# 7. CREAR USUARIO (si no existe)
# ============================================================
if ! id "$NEW_USER" &>/dev/null; then
  info "Creando usuario $NEW_USER..."
  useradd -m -s /bin/zsh "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
  usermod -aG docker "$NEW_USER"
  echo "⚠️  Recuerda establecer la contraseña con: passwd $NEW_USER"
  success "Usuario $NEW_USER creado"
else
  warn "Usuario $NEW_USER ya existe, añadiéndolo a grupos docker/sudo..."
  usermod -aG sudo "$NEW_USER"
  usermod -aG docker "$NEW_USER"
fi

# ============================================================
# 8. ZSH + OH MY ZSH + POWERLEVEL10K
# ============================================================
setup_zsh() {
  local TARGET_USER="$1"
  local TARGET_HOME
  TARGET_HOME=$(eval echo "~$TARGET_USER")

  info "Configurando Zsh + Oh My Zsh para $TARGET_USER..."

  # Oh My Zsh (sin modo interactivo)
  if [ ! -d "$TARGET_HOME/.oh-my-zsh" ]; then
    sudo -u "$TARGET_USER" sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended
  else
    warn "Oh My Zsh ya instalado para $TARGET_USER"
  fi

  # Powerlevel10k
  P10K_DIR="$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [ ! -d "$P10K_DIR" ]; then
    sudo -u "$TARGET_USER" git clone --depth=1 \
      https://github.com/romkatv/powerlevel10k.git \
      "$P10K_DIR"
  fi

  # Plugins útiles
  ZSH_PLUGINS_DIR="$TARGET_HOME/.oh-my-zsh/custom/plugins"
  sudo -u "$TARGET_USER" git clone --depth=1 \
    https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_PLUGINS_DIR/zsh-autosuggestions" 2>/dev/null || true
  sudo -u "$TARGET_USER" git clone --depth=1 \
    https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" 2>/dev/null || true

  # .zshrc
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

# Aliases útiles
alias ll='ls -lah'
alias gs='git status'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias nginx-reload='sudo systemctl reload nginx'

# Historial grande
HISTSIZE=10000
SAVEHIST=10000

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
ZSHRC

  chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.zshrc"
  chsh -s /bin/zsh "$TARGET_USER"
  success "Zsh configurado para $TARGET_USER"
}

setup_zsh root
setup_zsh "$NEW_USER"

# ============================================================
# 9. TMUX CONFIG
# ============================================================
info "Configurando tmux..."
cat > /root/.tmux.conf <<'TMUXCONF'
# Prefijo más cómodo
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Mouse activado
set -g mouse on

# Paneles con | y -
bind | split-window -h
bind - split-window -v

# Colores
set -g default-terminal "screen-256color"

# Barra de estado
set -g status-bg colour235
set -g status-fg colour136
set -g status-left '#[fg=colour166]#H '
set -g status-right '#[fg=colour136]%d/%m %H:%M'
TMUXCONF
cp /root/.tmux.conf "/home/$NEW_USER/.tmux.conf"
chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.tmux.conf"
success "Tmux configurado"

# ============================================================
# 10. N8N (opcional)
# ============================================================
if [ "$INSTALL_N8N" = "true" ]; then
  info "Instalando n8n con Docker..."
  docker pull n8nio/n8n
  docker run -d \
    --name n8n \
    --restart unless-stopped \
    -p 127.0.0.1:5678:5678 \
    -v n8n_data:/home/node/.n8n \
    n8nio/n8n
  success "n8n corriendo en puerto 5678"
fi

# ============================================================
# FIN
# ============================================================
echo ""
echo "╭──────────────────────────────────────────╮"
echo "│     ✅  Bootstrap completado             │"
echo "╰──────────────────────────────────────────╯"
echo ""
echo "  Próximos pasos:"
echo "  1. Establecer contraseña:  passwd $NEW_USER"
echo "  2. Configurar Powerlevel10k al hacer login: p10k configure"
echo "  3. Para instalar n8n:  INSTALL_N8N=true bash bootstrap.sh"
echo "  4. Para dominio+SSL:   certbot --nginx -d tudominio.com"
echo ""
