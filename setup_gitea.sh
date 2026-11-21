#!/usr/bin/env bash
set -euo pipefail

trap 'echo -e "\n\033[0;31m[BŁĄD] Skrypt przerwał działanie w linii $LINENO.\033[0m"' ERR

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}====================================================${NC}"
echo -e "${BLUE}       Konfigurator serwera Gitea (Docker)          ${NC}"
echo -e "${BLUE}====================================================${NC}"

# Funkcja sprawdzająca, czy port TCP na hoście jest wolny (0 = wolny, 1 = zajęty)
is_port_free() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ! ss -tln "sport = :${port}" 2>/dev/null | awk 'NR>1 {found=1} END {exit !found}'
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import socket, sys; s=socket.socket(); s.settimeout(0.2); sys.exit(0 if s.connect_ex(('127.0.0.1', int(sys.argv[1])))!=0 else 1)" "$port"
    else
        return 0
    fi
}

find_free_port() {
    local port="$1"
    while ! is_port_free "$port"; do
        port=$((port + 1))
    done
    echo "$port"
}

# 1. Docker i Compose
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Nie wykryto Dockera w systemie.${NC}"
    read -rp "Zainstalować Docker Engine i Docker Compose teraz? [t/N]: " INSTALL_DOCKER
    if [[ "${INSTALL_DOCKER,,}" == "t" || "${INSTALL_DOCKER,,}" == "y" ]]; then
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER" || true
    else
        echo -e "${RED}[x] Przerwano: wymagany jest Docker.${NC}"
        exit 1
    fi
fi

DOCKER_BIN="docker"
if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        DOCKER_BIN="sudo docker"
        echo -e "${YELLOW}[!] Brak uprawnień bez sudo do gniazda Dockera — używam 'sudo docker'.${NC}"
    else
        echo -e "${RED}[x] Demon Dockera nie odpowiada. Sprawdź: sudo systemctl status docker${NC}"
        exit 1
    fi
fi

if $DOCKER_BIN compose version >/dev/null 2>&1; then
    COMPOSE_CMD="$DOCKER_BIN compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="sudo docker-compose"
else
    echo -e "${RED}[x] Brak 'docker compose'. Zainstaluj: sudo apt install docker-compose-plugin${NC}"
    exit 1
fi

DEFAULT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
DEFAULT_IP=${DEFAULT_IP:-localhost}
SUGGESTED_HTTP=$(find_free_port 3000)
SUGGESTED_SSH=$(find_free_port 2222)

# 2. Konfiguracja
echo ""
read -rp "Katalog instalacji [domyślnie: $HOME/docker/gitea]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-"$HOME/docker/gitea"}

read -rp "Domena lub adres IP serwera [domyślnie: $DEFAULT_IP]: " SERVER_HOST
SERVER_HOST=${SERVER_HOST:-"$DEFAULT_IP"}

while true; do
    read -rp "Port HTTP interfejsu web [sugerowany wolny: $SUGGESTED_HTTP]: " HTTP_PORT
    HTTP_PORT=${HTTP_PORT:-$SUGGESTED_HTTP}
    if is_port_free "$HTTP_PORT"; then
        break
    else
        ALT_PORT=$(find_free_port "$HTTP_PORT")
        echo -e "${YELLOW}[!] Port $HTTP_PORT jest już zajęty. Spróbuj np. $ALT_PORT.${NC}"
    fi
done

while true; do
    read -rp "Port SSH dla operacji Git [sugerowany wolny: $SUGGESTED_SSH]: " SSH_PORT
    SSH_PORT=${SSH_PORT:-$SUGGESTED_SSH}
    if [[ "$SSH_PORT" == "$HTTP_PORT" ]]; then
        echo -e "${RED}[!] Port SSH nie może być taki sam jak port HTTP.${NC}"
        continue
    fi
    if is_port_free "$SSH_PORT"; then
        break
    else
        ALT_SSH=$(find_free_port "$SSH_PORT")
        echo -e "${YELLOW}[!] Port $SSH_PORT jest już zajęty. Spróbuj np. $ALT_SSH.${NC}"
    fi
done

read -rp "Zezwolić na samodzielną rejestrację użytkowników? [t/N]: " ALLOW_REG
if [[ "${ALLOW_REG,,}" == "t" || "${ALLOW_REG,,}" == "y" ]]; then
    DISABLE_REG="false"
else
    DISABLE_REG="true"
fi

read -rp "Wymagać logowania do przeglądania repozytoriów? [t/N]: " REQ_SIGNIN
if [[ "${REQ_SIGNIN,,}" == "t" || "${REQ_SIGNIN,,}" == "y" ]]; then
    REQUIRE_SIGNIN="true"
else
    REQUIRE_SIGNIN="false"
fi

read -rp "Tworzyć nowe repozytoria automatycznie przy pierwszym 'git push'? [T/n]: " AUTO_CREATE_REPO
if [[ "${AUTO_CREATE_REPO,,}" == "n" ]]; then
    PUSH_CREATE_USER="false"
    PUSH_CREATE_ORG="false"
else
    PUSH_CREATE_USER="true"
    PUSH_CREATE_ORG="true"
fi

echo ""
echo -e "${YELLOW}--- Konto administratora ---${NC}"
read -rp "Login administratora [domyślnie: admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -rp "E-mail administratora [domyślnie: admin@local.lan]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@local.lan"}

while true; do
    read -rsp "Hasło administratora (min. 8 znaków): " ADMIN_PASS
    echo ""
    if [[ ${#ADMIN_PASS} -ge 8 ]]; then
        break
    else
        echo -e "${RED}[!] Hasło musi mieć co najmniej 8 znaków.${NC}"
    fi
done

# 3. Generowanie sekretu dla bazy danych
if command -v openssl >/dev/null 2>&1; then
    DB_PASS=$(openssl rand -hex 16)
else
    DB_PASS=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)
fi

ROOT_URL="http://${SERVER_HOST}:${HTTP_PORT}/"
UID_VAL=$(id -u)
GID_VAL=$(id -g)

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Jeśli w katalogu działa już wcześniejszy stos, posprzątaj go czysto
$COMPOSE_CMD down --remove-orphans >/dev/null 2>&1 || true

echo -e "${BLUE}[*] Tworzenie pliku docker-compose.yml...${NC}"
cat > docker-compose.yml <<EOF
services:
  server:
    image: docker.gitea.com/gitea:latest
    container_name: gitea
    environment:
      - USER_UID=${UID_VAL}
      - USER_GID=${GID_VAL}
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=db:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=${DB_PASS}
      - GITEA__server__DOMAIN=${SERVER_HOST}
      - GITEA__server__SSH_DOMAIN=${SERVER_HOST}
      - GITEA__server__ROOT_URL=${ROOT_URL}
      - GITEA__server__SSH_PORT=${SSH_PORT}
      - GITEA__service__DISABLE_REGISTRATION=${DISABLE_REG}
      - GITEA__service__REQUIRE_SIGNIN_VIEW=${REQUIRE_SIGNIN}
      - GITEA__service__DEFAULT_KEEP_EMAIL_PRIVATE=true
      - GITEA__repository__ENABLE_PUSH_CREATE_USER=${PUSH_CREATE_USER}
      - GITEA__repository__ENABLE_PUSH_CREATE_ORG=${PUSH_CREATE_ORG}
      - GITEA__security__INSTALL_LOCK=true
    restart: unless-stopped
    networks:
      - gitea
    volumes:
      - ./gitea:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "${HTTP_PORT}:3000"
      - "${SSH_PORT}:22"
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    container_name: gitea_db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=${DB_PASS}
      - POSTGRES_DB=gitea
    networks:
      - gitea
    volumes:
      - ./postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea"]
      interval: 5s
      timeout: 5s
      retries: 10

networks:
  gitea:
    external: false
EOF

cat > .env.credentials <<EOF
GITEA_URL=${ROOT_URL}
SSH_PORT=${SSH_PORT}
PUSH_CREATE_USER=${PUSH_CREATE_USER}
PUSH_CREATE_ORG=${PUSH_CREATE_ORG}
ADMIN_USER=${ADMIN_USER}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASS=${ADMIN_PASS}
POSTGRES_DB=gitea
POSTGRES_USER=gitea
POSTGRES_PASS=${DB_PASS}
EOF
chmod 600 .env.credentials

# 4. Uruchomienie stosu i oczekiwanie na gotowość Gitea
echo -e "${BLUE}[*] Uruchamianie PostgreSQL oraz Gitea...${NC}"
$COMPOSE_CMD up -d

echo -e "${BLUE}[*] Oczekiwanie na uruchomienie serwisu Gitea...${NC}"
READY=0
for _ in {1..30}; do
    if curl -fsS "http://127.0.0.1:${HTTP_PORT}/api/healthz" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 2
done

if [[ "$READY" -eq 0 ]]; then
    echo -e "${YELLOW}[!] Gitea jeszcze nie odpowiedziała na /api/healthz — sprawdzam status kontenerów:${NC}"
    $COMPOSE_CMD ps -a
    echo -e "${YELLOW}[!] Ostatnie logi kontenera gitea:${NC}"
    $COMPOSE_CMD logs gitea --tail 25 || true
    exit 1
fi

# 5. Utworzenie konta administratora
echo -e "${BLUE}[*] Tworzenie konta administratora '${ADMIN_USER}'...${NC}"
if ! $DOCKER_BIN exec --user git gitea gitea admin user create \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --email "$ADMIN_EMAIL" \
    --admin \
    --must-change-password=false; then
    echo -e "${YELLOW}[!] Nie udało się utworzyć konta (może już istnieje). Sprawdź logi jeśli trzeba.${NC}"
fi

echo ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}   Gitea uruchomiona i gotowa!                      ${NC}"
echo -e "${GREEN}====================================================${NC}"
echo -e "Adres WWW:        ${BLUE}${ROOT_URL}${NC}"
echo -e "Port SSH Git:     ${BLUE}${SSH_PORT}${NC}"
echo -e "Auto-repo (push): ${BLUE}${PUSH_CREATE_USER}${NC}"
echo -e "Login admina:     ${BLUE}${ADMIN_USER}${NC}"
echo -e "Katalog danych:   ${BLUE}${INSTALL_DIR}${NC}"
echo -e "Poświadczenia:    ${YELLOW}${INSTALL_DIR}/.env.credentials${NC}"
echo ""
$COMPOSE_CMD ps
