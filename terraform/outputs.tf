output "picture_url" {
  description = "Адрес картинки в бакете (открывается из интернета без авторизации)"
  value       = local.picture_url
}

output "nlb_address" {
  description = "Внешний IP сетевого балансировщика (порт 80)"
  value = one([
    for l in yandex_lb_network_load_balancer.web.listener :
    one([for a in l.external_address_spec : a.address])
  ])
}

output "alb_address" {
  description = "Внешний IP Application Load Balancer (порт 80)"
  value       = yandex_alb_load_balancer.web.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
}

output "instance_group" {
  description = "Группа ВМ: id и имя target group NLB"
  value = {
    id = yandex_compute_instance_group.lamp.id
    # В режиме alb блока load_balancer у группы нет, поэтому try(): null вместо ошибки.
    target_group_id     = try(yandex_compute_instance_group.lamp.load_balancer[0].target_group_id, null)
    target_group_name   = try(yandex_compute_instance_group.lamp.load_balancer[0].target_group_name, null)
    alb_target_group_id = try(yandex_compute_instance_group.lamp.application_load_balancer[0].target_group_id, null)
  }
}

output "vms" {
  description = "ВМ группы: имя, внутренний и публичный IP"
  value = [
    for i in yandex_compute_instance_group.lamp.instances : {
      name        = i.name
      internal_ip = i.network_interface[0].ip_address
      public_ip   = i.network_interface[0].nat_ip_address
      status      = i.status
    }
  ]
}
