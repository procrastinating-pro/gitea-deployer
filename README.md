# Własny serwer Gitea w Dockerze (`setup_gitea.sh`)

Lekki, wieloużytkownikowy serwer Git w kontenerach **Docker** (`Gitea` + `PostgreSQL`), idealny do przechowywania kodu, konfiguracji, skryptów oraz notatek (np. w Markdownie / Obsidianie) z pełną historią zmian i kontrolą dostępu.

## Co robi skrypt `setup_gitea.sh`?

* Sprawdza obecność **Dockera** i **Docker Compose** (oraz pozwala doinstalować brakujące komponenty na systemach opartych na Debianie/Ubuntu).
* Wykrywa lub pozwala podać **adres IP / domenę** oraz sprawdza, czy wybrane porty **HTTP** i **SSH** są wolne.
* Konfiguruje obsługę **wielu użytkowników** (rejestracja otwarta lub zamknięta, wymóg logowania do przeglądania repozytoriów).
* Pozwala włączyć **automatyczne tworzenie repozytoriów przy pierwszym `git push`** (`ENABLE_PUSH_CREATE_USER` oraz `ENABLE_PUSH_CREATE_ORG`).
* Generuje losowe hasło do bazy **PostgreSQL**, tworzy `docker-compose.yml`, uruchamia stos, czeka na gotowość Gitea i zakłada **konto administratora** przez CLI.
* Zapisuje dane dostępowe i hasła w pliku `.env.credentials` (`chmod 600`).

---

## Szybki start

1. Pobierz lub zapisz skrypt jako `setup_gitea.sh` w wybranym katalogu.
2. Nadaj uprawnienia do uruchamiania i odpal przez `bash`:

```bash
chmod +x setup_gitea.sh
bash ./setup_gitea.sh
```

3. Po zakończeniu działania skryptu otwórz w przeglądarce adres `Adres WWW` wyświetlony na końcu (np. `http://192.168.1.133:3000/`) i zaloguj się na utworzone konto administratora.

---

## Zarządzanie kontenerami

Wszystkie polecenia wykonuj w katalogu instalacji (domyślnie `~/docker/gitea`):

```bash
cd ~/docker/gitea

# Status kontenerów
docker compose ps

# Podgląd logów na żywo
docker compose logs -f

# Zatrzymanie kontenerów
docker compose down

# Uruchomienie / przeładowanie po zmianach w docker-compose.yml
docker compose up -d
```

---

## Konfiguracja Git na komputerze klienta

### 1. Konfiguracja tożsamości Git (jednorazowo na każdym komputerze)

Przed wykonaniem pierwszego commita ustaw swoją nazwę użytkownika oraz adres e-mail (najlepiej taki sam, jaki został podany przy zakładaniu konta w Gitea, aby commity poprawnie łączyły się z Twoim profilem):

```bash
git config --global user.name "Twoje Imię lub Login"
git config --global user.email "twoj_email@local.lan"

# Opcjonalnie: domyślna nazwa głównej gałęzi oraz zapisywanie poświadczeń HTTP
git config --global init.defaultBranch main
git config --global credential.helper store
```

*(Wskazówka: `credential.helper store` zapamięta login i hasło/token po pierwszym logowaniu po HTTP, jeśli nie korzystasz z kluczy SSH).*

### 2. Konfiguracja klucza SSH (polecane)

Aby wypychać i pobierać zmiany po SSH bez wpisywania hasła:

```bash
ssh-keygen -t ed25519 -C "twoj_email@domena"
cat ~/.ssh/id_ed25519.pub
```

Skopiowany klucz publiczny wklej w Gitea w sekcji: **Avatar → Ustawienia → Klucze SSH i GPG → Dodaj klucz**.

Test połączenia (np. dla portu SSH `2222`):

```bash
ssh -T -p 2222 git@192.168.1.133
```

---

## Praca z repozytorium (`push`, `pull`, `clone`)

### 1. Nowe repozytorium z lokalnego katalogu

Jeśli włączyłeś automatyczne tworzenie repozytoriów przy `git push`, możesz wypchnąć nowy folder od razu pod jeszcze nieistniejącą nazwę repozytorium:

```bash
cd ~/moj-projekt
git init
git branch -M main
git add .
git commit -m "Pierwszy commit"
git remote add origin ssh://git@192.168.1.133:2222/TWOJ_LOGIN/nazwa-repo.git
git push -u origin main
```

### 2. Codzienna praca (`pull` i `push`)

```bash
# Pobranie zmian z serwera
git pull

# Wysłanie własnych zmian
git add .
git commit -m "Opis zmiany"
git push
```

---

## Praca z branchami

Gałęzie (*branches*) przydają się przy eksperymentach, większych zmianach lub pracy kilku osób na tym samym repozytorium:

```bash
# Utworzenie nowego brancha i przełączenie na niego
git switch -c nazwa-brancha

# Wysłanie nowego brancha na serwer Gitea
git push -u origin nazwa-brancha

# Powrót na główny branch main i aktualizacja
git switch main
git pull

# Scalenie zmian z brancha do main (alternatywnie użyj Pull Request w Gitea)
git merge nazwa-brancha
git push
```

---

## Zarządzanie wieloma użytkownikami

* **Dodawanie kont ręcznie (gdy rejestracja jest wyłączona):** Zaloguj się na konto administratora i przejdź do **Administracja serwera → Konta użytkowników → Utwórz konto**.
* **Praca zespołowa:** Utwórz **Organizację** (ikona `+` na górnym pasku → *Nowa organizacja*), dodaj do niej zespoły z odpowiednimi uprawnieniami (odczyt, zapis, administrator) i przypisz użytkowników.

---

## Rozwiązywanie typowych problemów

* **Błąd zajęcia portu (`Bind for 0.0.0.0:3000 failed: port is already allocated`)** — wybierz inny port HTTP w konfiguratorze (np. `3001`) lub sprawdź, co zajmuje port poleceniem `ss -tulpn | grep :3000`.
* **Brak połączenia w przeglądarce (`ERR_CONNECTION_REFUSED`)** — sprawdź `docker compose ps -a` oraz `docker compose logs gitea --tail 30`, upewnij się, że używasz właściwego portu i że zapora (`ufw`) nie blokuje ruchu.
* **Brak uprawnień do Dockera** — dodaj użytkownika do grupy `docker` (`sudo usermod -aG docker $USER`) i przeloguj się lub uruchom skrypt w środowisku z dostępem do `sudo`.

---

## Bezpieczeństwo i kopia zapasowa

* Dane aplikacji znajdują się w `./gitea`, a baza danych w `./postgres` (wewnątrz katalogu instalacji).
* Plik `.env.credentials` zawiera hasła i poświadczenia — nie wrzucaj go do publicznych repozytoriów i trzymaj z uprawnieniami `600`.
* Aby wykonać kopię zapasową, zatrzymaj kontenery (`docker compose down`) i zarchiwizuj cały katalog instalacji (`tar -czf gitea_backup.tar.gz ~/docker/gitea`).