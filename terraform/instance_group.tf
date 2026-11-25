###--- группа ВМ фиксированного размера с шаблоном LAMP ---###
resource "yandex_compute_instance_group" "lamp" {
  name               = "lamp-group"
  description        = "Три ВМ с LAMP; стартовая страница ссылается на картинку из бакета"
  folder_id          = var.folder_id
  service_account_id = yandex_iam_service_account.ig.id

  # Нужно для чистого destroy: по умолчанию группа от удаления не защищена, но фиксируем явно.
  deletion_protection = false

  # Группа создаёт ресурсы от имени ig-sa — роли должны успеть «разъехаться» (см. iam.tf).
  depends_on = [time_sleep.wait_for_iam]

  instance_template {
    platform_id = "standard-v3"
    # Имя и hostname ВМ строятся по шаблону: lamp-1, lamp-2, lamp-3.
    name        = "lamp-{instance.index}"
    hostname    = "lamp-{instance.index}"
    description = "ВМ LAMP из группы lamp-group"

    resources {
      cores         = 2
      memory        = 2
      core_fraction = 20 # 2 vCPU @ 20 % — укладываемся в квоту зоны «2 эффективных ядра»: 3 ВМ × 0.4
    }

    boot_disk {
      initialize_params {
        image_id = var.lamp_image_id
        size     = var.disk_size_gb
        type     = "network-hdd" # квота зоны: HDD 20 ГиБ, SSD 10 ГиБ
      }
    }

    network_interface {
      network_id         = yandex_vpc_network.this.id
      subnet_ids         = [yandex_vpc_subnet.public.id]
      nat                = true # ВМ в public подсети — с публичным IP (по заданию)
      security_group_ids = [yandex_vpc_security_group.web.id]
    }

    # Страница строится из шаблона; ссылка на картинку берётся из реального адреса объекта в бакете.
    metadata = {
      user-data = templatefile("${path.module}/files/user-data.sh.tftpl", {
        picture_url = local.picture_url
      })
    }
  }

  # Фиксированный размер: группа сама держит ровно 3 ВМ и пересоздаёт пропавшие.
  scale_policy {
    fixed_scale {
      size = var.instance_count
    }
  }

  allocation_policy {
    zones = [var.zone]
  }

  # Обновление «по одной ВМ»: сначала удаляем старую, потом создаём новую (max_expansion = 0),
  # иначе упрёмся в квоту диска зоны (HDD 20 ГиБ): 3 × 5 + ещё одна = 20 ГиБ впритык.
  deploy_policy {
    max_unavailable = 1
    max_expansion   = 0
  }

  # Проверка состояния ВМ самой группой (auto-healing): ВМ, не отвечающую на HTTP :80,
  # группа пересоздаёт. Это отдельная проверка от проверки балансировщика (nlb.tf):
  # балансировщик только перестаёт слать трафик, а группа — лечит.
  health_check {
    interval            = 5
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 3
    http_options {
      port = 80
      path = "/"
    }
  }

  # Блок load_balancer заставляет группу создать target group и сам держать в ней адреса ВМ:
  # новая ВМ добавляется, удалённая убирается. Отдельный yandex_lb_target_group не нужен.
  # Блоки load_balancer и application_load_balancer взаимоисключающие (ограничение API группы ВМ),
  # поэтому включается один из них — по переменной balancer.
  dynamic "load_balancer" {
    for_each = var.balancer == "nlb" ? [1] : []
    content {
      target_group_name        = "lamp-nlb-tg"
      target_group_description = "Target group для сетевого балансировщика, ведётся группой lamp-group"
    }
  }

  # То же для Application Load Balancer (L7): target group для backend group из alb.tf.
  dynamic "application_load_balancer" {
    for_each = var.balancer == "alb" ? [1] : []
    content {
      target_group_name        = "lamp-alb-tg"
      target_group_description = "Target group для Application Load Balancer, ведётся группой lamp-group"
    }
  }
}
