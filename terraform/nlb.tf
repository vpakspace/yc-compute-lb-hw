###--- сетевой балансировщик (Network Load Balancer, L4) ---###
resource "yandex_lb_network_load_balancer" "web" {
  name        = "lamp-nlb"
  description = "Внешний сетевой балансировщик перед группой lamp-group"
  type        = "external"

  listener {
    name        = "http"
    port        = 80
    target_port = 80
    protocol    = "tcp"
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  # Цели подключаются только в режиме balancer = "nlb": в режиме "alb" группа ВМ ведёт target group для ALB,
  # а у NLB целей нет (статус INACTIVE) — сам балансировщик и его публичный адрес при этом остаются.
  dynamic "attached_target_group" {
    for_each = var.balancer == "nlb" ? [1] : []
    content {
      # Target group создала сама группа ВМ (блок load_balancer в instance_group.tf).
      target_group_id = yandex_compute_instance_group.lamp.load_balancer[0].target_group_id

      # Проверка состояния на стороне балансировщика: ВМ, не ответившая HTTP 200 на GET /,
      # выводится из ротации через unhealthy_threshold × interval = 4 с.
      healthcheck {
        name                = "http"
        interval            = 2
        timeout             = 1
        unhealthy_threshold = 2
        healthy_threshold   = 2
        http_options {
          port = 80
          path = "/"
        }
      }
    }
  }
}
