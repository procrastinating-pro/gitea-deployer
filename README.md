# Gitea Deployer

Interaktywny konfigurator i skrypt wdrożeniowy dla skonteneryzowanej instancji **Gitea**. Automatyzuje przygotowanie plików konfiguracyjnych (`docker-compose.yml`, `.env`, `app.ini`), katalogów wolumenów oraz uruchomienie kontenera bez konieczności ręcznego pisania boilerplate'u.

## Wymagania

* **Docker** oraz **Docker Compose** (v2+)
* System Linux z powłoką **Bash** (wymagane wsparcie dla podstawienia procesów `<(...)`)
* `curl` lub `git`

## Szybki start

Uruchom konfigurator bezpośrednio jedną komendą (zachowuje pełną interaktywność terminala):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/procrastinating-pro/gitea-deployer/refs/heads/main/setup_gitea.sh)
```

### Alternatywnie: pobranie i przegląd kodu przed uruchomieniem

Jeśli wolisz najpierw sprawdzić zawartość skryptu lub zachować go lokalnie:

```bash
curl -fsSLO https://raw.githubusercontent.com/procrastinating-pro/gitea-deployer/refs/heads/main/setup_gitea.sh
chmod +x setup_gitea.sh
./setup_gitea.sh
```

Lub poprzez sklonowanie repozytorium:

```bash
git clone https://github.com/procrastinating-pro/gitea-deployer.git
cd gitea-deployer
chmod +x setup_gitea.sh
./setup_gitea.sh
```

## Co robi skrypt?

1. **Zbiera parametry konfiguracji** (porty HTTP/SSH, domena, ścieżki wolumenów, ustawienia bazy danych).
2. **Generuje pliki wdrożeniowe** (`docker-compose.yml` / `.env`) dopasowane do podanych wartości.
3. **Inicjalizuje strukturę katalogów** pod trwałe dane repozytoriów i konfigurację Gitea.
4. **Uruchamia kontener** w tle i weryfikuje status wdrożenia.

## Zarządzanie instancją

Po zakończeniu działania skryptu możesz zarządzać kontenerem standardowymi poleceniami Docker Compose w katalogu projektu:

```bash
# Podgląd logów
docker compose logs -f

# Zatrzymanie kontenerów
docker compose down

# Aktualizacja obrazu Gitea
docker compose pull && docker compose up -d
```