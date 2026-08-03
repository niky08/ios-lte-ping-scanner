# LTE L3 Scanner (iOS)

Проверка L3-доступности на **LTE** (что реально не режет оператор).

Два режима:

1. **WL+EU TCP** — база из архивов сервера (`l3_master_targets.json`)
   - **Этап 1:** TCP к каждому уникальному `host` / `domain` (порт по умолчанию 443)
   - **Этап 2:** TCP к `host:port` каждого тега, прошедшего этап 1
   - **Экспорт JSON** — отдать на сервер для HEAD probe
2. **ICMP диапазон** — старый режим `111.88.1.x`

## База целей

Сервер: `/opt/vpn-master/scripts/extract_l3_targets.py`

```bash
python3 /opt/vpn-master/scripts/extract_l3_targets.py \
  -o /opt/vpn-master/data/l3_master_targets.json
```

Сейчас в базе (из 105 архивов WL+EU):

| | |
|---|---|
| Endpoint (tag+host+port) | ~54 833 |
| Уникальных host/domain | ~5 571 |
| Уникальных host:port | ~6 219 |

Файл в приложении: `PingScanner/Resources/l3_master_targets.json` (можно обновить импортом).

## Сборка IPA (GitHub Actions)

1. https://github.com/niky08/ios-lte-ping-scanner/actions
2. **Build iOS IPA** → Run workflow
3. Artifacts → `PingScanner.ipa`

Сканируйте на **реальном iPhone + LTE**, не Wi‑Fi.

## Экспорт для сервера

После этапа 2 → **Экспорт JSON**. Формат:

```json
{
  "alive_hosts": [{"host":"1.2.3.4","port":443,"latencyMs":42}],
  "alive_endpoints": [{"tag":"wl-…","host":"…","port":443,"latencyMs":55,"source":"wl"}]
}
```

Этот файл — whitelist для L3; дальше на сервере HEAD probe только по `alive_endpoints`.

## Идентификаторы

| | |
|---|---|
| Bundle ID | `app.aries712.garlic3686` |
| App Group | `group.27d6c67cc354451e.4` |
