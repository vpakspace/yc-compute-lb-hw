#!/usr/bin/env bash
# Проверка отказоустойчивости: пока на адрес балансировщика идёт поток запросов (1 в секунду), удаляем две из трёх ВМ,
# затем ждём, пока группа сама вернёт ВМ, а балансировщик — все цели в HEALTHY.
# Всё пишется в один лог с метками времени: строки `### ...` — события, остальные — результат каждого запроса
#   `HH:MM:SS  HTTP <код>  <имя ВМ, которая ответила>  <время ответа>`.
# В конце — сводка: сколько запросов вернули 200, сколько оборвались.
#
# Запуск:  ./scripts/failover.sh nlb     (группа в режиме balancer=nlb, лог logs/06_failover_nlb.log)
#          ./scripts/failover.sh alb     (группа в режиме balancer=alb, лог logs/09_failover_alb.log)
# Длится 3–5 минут; ВМ удаляются по-настоящему, группа их пересоздаёт.
#
# Про «паузы измерителя»: на машине управления (VirtualBox VM) гостевая ОС иногда замирает на десятки секунд, и поток
# запросов в это время не идёт. Такие паузы помечаются в логе, чтобы не принять их за сбой балансировщика.
set -uo pipefail

MODE=${1:-nlb}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/terraform" || exit 1
export TF_CLI_CONFIG_FILE="$PWD/.terraformrc"
export PATH="$HOME/bin:$PATH"

case "$MODE" in
  nlb)
    LOG="$ROOT/logs/06_failover_nlb.log"
    ADDR=$(terraform output -raw nlb_address)
    TG=$(terraform output -json instance_group | jq -r .target_group_id)
    state_cmd() { yc load-balancer network-load-balancer target-states lamp-nlb --target-group-id "$TG" "$@"; }
    ;;
  alb)
    LOG="$ROOT/logs/09_failover_alb.log"
    ADDR=$(terraform output -raw alb_address)
    state_cmd() {
      yc application-load-balancer load-balancer target-states lamp-alb \
        --target-group-name lamp-alb-tg --backend-group-name lamp-backend-group "$@"
    }
    ;;
  *) echo "использование: $0 [nlb|alb]" >&2; exit 2 ;;
esac

WORK=$(mktemp -d)
STOP="$WORK/stop"
: > "$LOG"

ts()   { date +%H:%M:%S; }
note() { printf '%s  ### %s\n' "$(ts)" "$*" >> "$LOG"; }
# Состояния целей в лог. У NLB таблица `yc` уже содержит статус; у ALB в таблице только адреса — берём JSON.
states() {
  if [ "$MODE" = alb ]; then
    state_cmd --format json 2>&1 | jq -r '.[] | "  \(.target.ip_address)  \(.status.zone_statuses[0].status // "?")"' |
      sed 's/^/                  /' >> "$LOG"
  else
    state_cmd 2>&1 | sed 's/^/                  /' >> "$LOG"
  fi
}
running() { yc compute instance list --format json | jq '[.[] | select(.status == "RUNNING")] | length'; }
# Число целей в HEALTHY: ищем объекты со status=HEALTHY на любой глубине — у NLB ответ плоский, у ALB вложенный.
healthy() { state_cmd --format json 2>/dev/null | jq '[.. | objects | select(.status? == "HEALTHY")] | length'; }

# Фоновый поток запросов: код ответа и имя ВМ из страницы. 000 — соединение не установилось / таймаут.
probe() {
  local prev now
  prev=$(date +%s)
  while [ ! -e "$STOP" ]; do
    : > "$WORK/body" # иначе при обрыве в «ответившие» попадёт имя ВМ из предыдущего запроса
    out=$(curl -s -o "$WORK/body" -w '%{http_code} %{time_total}' --connect-timeout 1 --max-time 2 "http://$ADDR/")
    host=$(grep -o 'lamp-[0-9]*' "$WORK/body" 2>/dev/null | head -n 1)
    printf '%s  HTTP %s  %-7s %ss\n' "$(ts)" "${out% *}" "${host:--}" "${out#* }" >> "$LOG"
    # Запрос в секунду не может «молчать» дольше нескольких секунд (у curl --max-time 2). Если пауза длиннее —
    # замирал сам измеритель (гостевая ОС этой VM), а не балансировщик; помечаем.
    now=$(date +%s)
    [ $((now - prev)) -gt 6 ] && printf '%s  ### пауза измерителя %d с (запросы в это время не выполнялись)\n' "$(ts)" $((now - prev)) >> "$LOG"
    prev=$now
    sleep 1
  done
}

mapfile -t VMS < <(yc compute instance list --format json | jq -r '.[].name' | sort)
note "старт ($MODE): балансировщик $ADDR, ВМ в группе: ${VMS[*]}"
states
probe &
PROBE_PID=$!
sleep 8

note "удаляю ${VMS[0]}"
yc compute instance delete --name "${VMS[0]}" --async > /dev/null 2>&1
sleep 15
note "состояние целей после удаления одной ВМ"
states

note "удаляю ${VMS[1]} — остаётся одна ВМ (${VMS[2]})"
yc compute instance delete --name "${VMS[1]}" --async > /dev/null 2>&1
sleep 15
note "состояние целей после удаления двух ВМ"
states

# Ждём, пока группа восстановит размер (3 ВМ RUNNING), а балансировщик увидит три HEALTHY цели. Не дольше 6 минут.
for _ in $(seq 72); do
  [ "$(running)" = 3 ] && [ "$(healthy)" = 3 ] && break
  sleep 5
done
note "группа восстановила размер: RUNNING=$(running), HEALTHY=$(healthy)"
states
sleep 8

touch "$STOP"; wait "$PROBE_PID" 2>/dev/null
{
  echo
  echo "### сводка по запросам к балансировщику ($MODE):"
  grep -E '  HTTP [0-9]+  ' "$LOG" | awk '{c[$3]++; if ($3 == 200) h[$4]++} END {
    for (k in c) printf "    HTTP %s: %d\n", k, c[k]
    for (k in h) printf "    ответов от %s: %d\n", k, h[k]}' | sort
} >> "$LOG"
rm -rf "$WORK"
echo "готово: $LOG"
