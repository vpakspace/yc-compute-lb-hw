###--- Application Load Balancer (L7) — дополнительная часть задания ---###
# Цепочка: слушатель :80 → HTTP-роутер → виртуальный хост → backend group → target group группы ВМ.
# В отличие от NLB (L4, просто пересылает пакеты) ALB терминирует HTTP-соединение, сам ходит на ВМ
# и проверяет состояние по HTTP-запросу.

# Backend group: куда слать запросы и как проверять, что ВМ жива.
# Существует только в режиме balancer = "alb": ссылается на target group, которую ведёт группа ВМ
# (в режиме "nlb" этой target group нет).
resource "yandex_alb_backend_group" "web" {
  count       = var.balancer == "alb" ? 1 : 0
  name        = "lamp-backend-group"
  description = "Backend group для lamp-group: HTTP :80 с проверкой GET /"

  http_backend {
    name   = "lamp-backend"
    weight = 1
    port   = 80
    # Target group создала сама группа ВМ (блок application_load_balancer в instance_group.tf).
    target_group_ids = [yandex_compute_instance_group.lamp.application_load_balancer[0].target_group_id]

    # Проверка состояния: ВМ, не ответившая 2xx на GET /, выводится из ротации.
    healthcheck {
      timeout             = "1s"
      interval            = "2s"
      healthy_threshold   = 2
      unhealthy_threshold = 2
      http_healthcheck {
        path = "/"
      }
    }
  }
}

# HTTP-роутер: набор виртуальных хостов, к которому привязывается слушатель.
resource "yandex_alb_http_router" "web" {
  name        = "lamp-router"
  description = "Роутер ALB для lamp-group"
}

# Виртуальный хост без authority: ловит запросы с любым Host, всё направляет в backend group.
# В режиме "nlb" роутер остаётся пустым, и ALB отвечает 404 — он создан, но трафик на группу не пускает.
resource "yandex_alb_virtual_host" "web" {
  count          = var.balancer == "alb" ? 1 : 0
  name           = "lamp-vhost"
  http_router_id = yandex_alb_http_router.web.id

  route {
    name = "all"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web[0].id
        timeout          = "10s"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "web" {
  name        = "lamp-alb"
  description = "Внешний Application Load Balancer перед группой lamp-group"
  network_id  = yandex_vpc_network.this.id

  # Подсеть одна (по заданию), поэтому и узел балансировщика один — в той же зоне, что и ВМ.
  # Для отказоустойчивости ALB нужна подсеть в каждой зоне размещения; здесь это сознательное упрощение.
  allocation_policy {
    location {
      zone_id   = var.zone
      subnet_id = yandex_vpc_subnet.public.id
    }
  }

  listener {
    name = "http"
    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.web.id
      }
    }
  }
}
