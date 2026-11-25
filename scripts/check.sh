#!/usr/bin/env bash
# Проверка стенда после `terraform apply`. Пишет логи в logs/ (без цветов; `$ ` в начале строки — введённая команда):
#   03 — картинка в бакете: HTTP 200 анонимно, а список объектов бакета анонимам закрыт;
#   04 — группа ВМ: три ВМ RUNNING, у каждой своя страница со ссылкой на картинку, health check группы;
#   05 — балансировщик: все цели HEALTHY, 30 запросов на его адрес расходятся по трём ВМ
#        (NLB → logs/05_nlb.log, ALB → logs/08_alb.log).
# Использует terraform output, поэтому адреса и имена нигде не зашиты.
#
# Запуск:  ./scripts/check.sh nlb     (группа в режиме balancer=nlb)
#          ./scripts/check.sh alb     (группа в режиме balancer=alb; шаги 03 и 04 перезаписываются)
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOGS="$ROOT/logs"
cd "$ROOT/terraform" || exit 1
export TF_CLI_CONFIG_FILE="$PWD/.terraformrc"
export PATH="$HOME/bin:$PATH"

MODE=${1:-nlb}
PIC=$(terraform output -raw picture_url)
BUCKET_HOST=$(echo "$PIC" | awk -F/ '{print $3}')
PROMPT="$USER@$(hostname):~/yc-compute-lb-hw/terraform\$"

# Печатает команду с приглашением и выполняет её (stderr тоже в лог).
run() {
  printf '%s %s\n' "$PROMPT" "$*"
  eval "$*" 2>&1
  echo
}

# ───────────────────────── 03: бакет ─────────────────────────
{
  run "curl -sS -o /dev/null -w 'HTTP %{http_code}, %{content_type}, %{size_download} байт\n' $PIC"
  run "curl -sSI $PIC | head -n 8"
  echo "# Листинг бакета анонимно должен быть закрыт (list = false в anonymous_access_flags):"
  run "curl -sS -w '\nHTTP %{http_code}\n' https://$BUCKET_HOST/"
} > "$LOGS/03_bucket.log"

# ───────────────────────── 04: группа ВМ ─────────────────────────
{
  run "yc compute instance-group list-instances --name lamp-group"
  run "yc compute instance list"
  # Каждая ВМ отдаёт свою страницу напрямую (минуя балансировщик). Публичный адрес части ВМ может быть недоступен
  # с машины управления (маршрут до отдельных адресов YC; ICMP при этом идёт) — тогда честно пишем «нет ответа»:
  # что ВМ при этом жива, видно по шагу 05 (она отвечает через балансировщик).
  for ip in $(terraform output -json vms | jq -r '.[].public_ip'); do
    run "curl -s --max-time 5 http://$ip/ | grep -E 'Отвечает|href=' || echo '(нет ответа за 5 с)'"
  done
  run "yc compute instance-group get --name lamp-group --format json | jq '{name, status, scale_policy, health_checks_spec, load_balancer_state, application_load_balancer_state}'"
} > "$LOGS/04_group.log"

# ───────────────────────── 05: балансировщик ─────────────────────────
case "$MODE" in
  nlb)
    ADDR=$(terraform output -raw nlb_address)
    TG=$(terraform output -json instance_group | jq -r .target_group_id)
    OUT="$LOGS/05_nlb.log"
    {
      run "yc load-balancer network-load-balancer get --name lamp-nlb"
      run "yc load-balancer network-load-balancer target-states lamp-nlb --target-group-id $TG"
    } > "$OUT"
    ;;
  alb)
    ADDR=$(terraform output -raw alb_address)
    OUT="$LOGS/08_alb.log"
    {
      run "yc application-load-balancer load-balancer get --name lamp-alb"
      run "yc application-load-balancer backend-group get --name lamp-backend-group"
      # В таблице yc у ALB только адреса, статус — в JSON: печатаем «IP целевой ВМ — статус».
      run "yc application-load-balancer load-balancer target-states lamp-alb --target-group-name lamp-alb-tg --backend-group-name lamp-backend-group --format json | jq -r '.[] | \"\(.target.ip_address)  \(.status.zone_statuses[0].status)\"'"
    } > "$OUT"
    ;;
  *) echo "использование: $0 [nlb|alb]" >&2; exit 2 ;;
esac
{
  echo "# 30 запросов на $ADDR — сколько раз ответила каждая ВМ:"
  run "for i in \$(seq 30); do curl -s --max-time 3 http://$ADDR/ | grep -o 'lamp-[0-9]*'; done | sort | uniq -c"
} >> "$OUT"

echo "готово ($MODE): $LOGS/03_bucket.log 04_group.log $(basename "$OUT")"
