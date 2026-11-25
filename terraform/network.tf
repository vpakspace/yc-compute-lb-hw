###--- VPC и публичная подсеть ---###
# Та же сеть, что в предыдущем ДЗ блока 15 («Организация сети»): netology-vpc и подсеть public.
# Приватной подсети и NAT-инстанса здесь нет — задание про одну public подсеть.
resource "yandex_vpc_network" "this" {
  name        = var.vpc_name
  description = "VPC для ДЗ «Вычислительные мощности. Балансировщики нагрузки»"
}

resource "yandex_vpc_subnet" "public" {
  name           = "public"
  description    = "Публичная подсеть: ВМ группы lamp-group с публичными IP"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.public_cidr]
}

###--- группа безопасности ВМ ---###
# Входящие: только HTTP (80). SSH не открываем вовсе: ВМ создаёт группа, заходить на них не нужно —
# страница строится cloud-init'ом, диагностика идёт через `yc compute instance get-serial-port-output`.
# Исходящие: всё разрешено.
# Проверки состояния и клиентов NLB отдельным правилом выделять не нужно: NLB не терминирует соединение,
# а пересылает пакеты с исходным адресом клиента (проверки идут с 198.18.235.0/24 и 198.18.248.0/24) —
# оба случая покрывает правило «80/tcp с 0.0.0.0/0».
resource "yandex_vpc_security_group" "web" {
  name        = "lamp-web-sg"
  description = "ВМ группы lamp-group: входящий HTTP, исходящий — любой"
  network_id  = yandex_vpc_network.this.id

  ingress {
    description    = "HTTP от клиентов и проверок состояния NLB/ALB"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Любой исходящий трафик"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
