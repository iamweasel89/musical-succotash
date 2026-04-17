# Внешний доступ к отладочному API через Tailscale Funnel

Как открыть мой (Claude) доступ к `/state`, `/screen`, `/canvas` на телефоне, не выходя в паблик-интернет без TLS и без публичного IP.

## Схема

```
я (curl в Bash) ──HTTPS──▶ windows-3tm8vsu.tail60e676.ts.net  (Funnel-нода, Win11)
                                     │
                                     │  localhost:8081 (netsh portproxy v4+v6)
                                     │  tailnet (Tailscale 100.x IP)
                                     ▼
                              moto-g15-power (Android, 100.117.173.10)
                                     │
                                     ▼  localhost
                              debug server  (порт 8080 по умолчанию)
```

Funnel-нода = **windows-3tm8vsu** (у неё уже включен Funnel в admin-панели).
Телефон-источник = **moto-g15-power** → `100.117.173.10` в тайлнете.
Дефолт-порт сервера = `8080` (настраивается в Settings → Отладка).

## Почему нужен portproxy

`tailscale funnel` не умеет проксировать на удалённый tailnet-IP напрямую — команда принимается, но траффик не идёт (Ray ID в логах не появляется). Поэтому на windows-3tm8vsu нужен локальный форвард `localhost:8081 → 100.117.173.10:8080`, и funnel уже на `localhost:8081`.

Windows портпрокси на `127.0.0.1` не покрывает IPv6-localhost `[::1]`, поэтому нужен и v4, и v6 рулз. Иначе Tailscale-демон (SYSTEM) будет резолвить `localhost` в `::1` и таймаутить.

## Пошагово

### На телефоне

1. Мастерская → Отладка → включить «Debug server».
2. Скопировать токен (кнопка рядом с X-Debug-Token).
3. Убедиться что сервер отвечает на `100.117.173.10:8080` (в PowerShell на любой машине тайлнета: `curl http://100.117.173.10:8080/ -UseBasicParsing -TimeoutSec 5`).

### На windows-3tm8vsu (Win11, Funnel) — **Run as Administrator**

**Первый раз** (правила portproxy + firewall сохраняются между перезагрузками):

```powershell
netsh interface portproxy add v4tov4 listenport=8081 listenaddress=127.0.0.1 connectport=8080 connectaddress=100.117.173.10

netsh interface portproxy add v6tov4 listenport=8081 listenaddress=[::1] connectport=8080 connectaddress=100.117.173.10

New-NetFirewallRule -DisplayName "tailscale-portproxy-8081" -Direction Inbound -Protocol TCP -LocalPort 8081 -Action Allow
```

**Запустить Funnel** (каждый раз при старте):

```powershell
tailscale funnel --bg --https=443 http://localhost:8081
tailscale funnel status
```

Должно показать публичный URL: `https://windows-3tm8vsu.tail60e676.ts.net/`.

### Сообщить мне

Отдать мне (Claude):

- Публичный URL (`https://windows-3tm8vsu.tail60e676.ts.net`)
- Отладочный токен

Я буду дёргать:

```bash
curl -H "X-Debug-Token: <TOKEN>" https://windows-3tm8vsu.tail60e676.ts.net/state
curl -H "X-Debug-Token: <TOKEN>" https://windows-3tm8vsu.tail60e676.ts.net/screen
```

## Остановить

На windows-3tm8vsu:

```powershell
tailscale funnel --https=443 off
```

Или `tailscale funnel reset` — сбрасывает все funnel/serve правила.

Portproxy и firewall-правило оставляй — они не мешают пока не включён funnel.

## Убрать portproxy / firewall (если надо)

```powershell
netsh interface portproxy delete v4tov4 listenport=8081 listenaddress=127.0.0.1
netsh interface portproxy delete v6tov4 listenport=8081 listenaddress=[::1]
Remove-NetFirewallRule -DisplayName "tailscale-portproxy-8081"
```

## Траблшутинг

- **Таймаут** при `curl` на `https://windows-3tm8vsu.*.ts.net/*` — чаще всего Funnel не видит `localhost:8081`. Проверь: `Invoke-WebRequest http://127.0.0.1:8081/ -UseBasicParsing` (должен вернуть HTML debug-страницу). Если локально работает, но Funnel нет — не хватает IPv6 portproxy или firewall.
- **`403`** — не передал токен или в Settings не тот порт.
- **Телефон `.10` не отвечает локально** — Tailscale на телефоне выключен, или приложение hex-canvas закрыто (debug-сервер останавливается при выгрузке).
- **Windows-ноду выключили** — Funnel пропадает. Нужно держать её онлайн пока работаем.

## Почему не через телефон напрямую

`tailscale funnel` на Android без Termux не работает — нет CLI. Использовать Funnel-ноду на ПК как прокси к телефону проще и не требует ставить Termux + tailscaled.

## Альтернатива: SSH-туннель через pinggy (когда Tailscale недоступен)

Если windows-3tm8vsu выключена или tailnet не работает, быстрый обходной путь через SSH на порту 443 (обычно открыт):

```powershell
ssh -p 443 -o StrictHostKeyChecking=no -R 0:100.117.173.10:8080 a.pinggy.io
```

Получаешь временный URL `*.run.pinggy-free.link` (живёт 60 минут). Pinggy требует только исходящий 443 — проходит даже через жёсткие файрволы.

