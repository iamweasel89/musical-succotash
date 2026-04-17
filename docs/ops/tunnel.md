# Внешний доступ к отладочному API через Tailscale Funnel

Как открыть мой (Claude) доступ к `/state`, `/screen`, `/canvas` на телефоне, не выходя в паблик-интернет без TLS и без публичного IP.

## Схема

```
я (curl в Bash) ──HTTPS──▶ windows-3tm8vsu.<tailnet>.ts.net  (Funnel-нода, Win11)
                                     │
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

## Пошагово

### На телефоне

1. Мастерская → Отладка → включить «Debug server».
2. Скопировать токен (кнопка «Скопировать токен» или GET `/` без авторизации → в `/ips` увидишь текущие IP).
3. Убедиться что сервер ответил: на ПК в той же сети открыть `http://100.117.173.10:8080/` — должна отдаться help-страничка.

### На windows-3tm8vsu (Win11, Funnel)

В PowerShell / cmd:

```powershell
tailscale funnel --bg --https=443 http://100.117.173.10:8080
```

Проверить:

```powershell
tailscale funnel status
```

Должно показать публичный URL вида `https://windows-3tm8vsu.<tailnet>.ts.net/`.

### Сообщить мне

Отдать мне (Claude):

- Публичный URL (`https://windows-3tm8vsu.<tailnet>.ts.net`)
- Отладочный токен

Я буду дёргать:

```bash
curl -H "X-Debug-Token: <TOKEN>" https://windows-3tm8vsu.<tailnet>.ts.net/screen
```

## Остановить

На windows-3tm8vsu:

```powershell
tailscale funnel --https=443 off
```

Или `tailscale funnel reset` — сбрасывает все funnel/serve правила.

## Если IP телефона изменился

Tailscale IP (100.117.173.10) закреплён за устройством и не меняется пока устройство в тайлнете. Если всё же перепривязали — обновить команду funnel с новым IP из admin-панели.

## Траблшутинг

- **`403` на все запросы** — не передал токен или в Settings не тот порт.
- **Funnel недоступен** — в admin-панели Tailscale → ACL → проверить что для ноды разрешён `funnel` (атрибут `funnel = []` в policy).
- **Телефон `.10` не отвечает** — на телефоне Tailscale не запущен или приложение hex-canvas закрыто (debug server останавливается при выгрузке приложения).
- **Windows-ноду выключили** — Funnel пропадает. Нужно держать её онлайн пока работаем.

## Почему не через телефон напрямую

`tailscale funnel` на Android без Termux не работает — нет CLI. Использовать Funnel-ноду на ПК как прокси к телефону проще и не требует ставить Termux + tailscaled.
