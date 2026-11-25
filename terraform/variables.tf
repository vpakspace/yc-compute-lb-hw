###--- доступ к облаку ---###

variable "cloud_id" {
  type        = string
  description = "ID облака (https://console.yandex.cloud/cloud)"
}

variable "folder_id" {
  type        = string
  description = "ID каталога (folder), в котором создаются все ресурсы"
}

variable "zone" {
  type        = string
  default     = "ru-central1-a"
  description = "Зона доступности: подсеть public и все ВМ группы — в одной зоне (по заданию подсеть одна)"
}

variable "sa_key_file" {
  type        = string
  default     = "~/.authorized_key.json"
  description = "Путь к авторизованному ключу сервисного аккаунта terraform (вне репозитория)"
}

###--- сеть ---###

variable "vpc_name" {
  type        = string
  default     = "netology-vpc"
  description = "Имя VPC-сети (то же, что в предыдущем ДЗ блока 15)"
}

variable "public_cidr" {
  type        = string
  default     = "192.168.10.0/24"
  description = "CIDR публичной подсети `public` (то же, что в предыдущем ДЗ)"
}

###--- Object Storage ---###

variable "bucket_name" {
  type        = string
  default     = "vpakspace-20261125"
  description = "Имя бакета: «имя_студента_дата». Имена бакетов уникальны на весь Yandex Cloud"
}

variable "picture_key" {
  type        = string
  default     = "picture.png"
  description = "Имя объекта (картинки) в бакете"
}

variable "picture_file" {
  type        = string
  default     = "files/picture.png"
  description = "Локальный файл картинки (создаётся scripts/make_picture.py)"
}

###--- группа ВМ ---###

variable "lamp_image_id" {
  type        = string
  default     = "fd827b91d99psvq5fjit"
  description = "Образ LAMP из standard-images (рекомендован заданием)"
}

variable "balancer" {
  type        = string
  default     = "nlb"
  description = <<-EOT
    К какому балансировщику подключена группа ВМ: "nlb" (сетевой, L4 — основная часть задания) или
    "alb" (Application Load Balancer, L7 — дополнительная часть). Одновременно — только к одному: API группы ВМ
    отвечает "Only one of (load_balancer_spec, application_load_balancer_spec) can be specified".
    Смена значения пересоздаёт группу (провайдер помечает оба блока как forces replacement).
  EOT

  validation {
    condition     = contains(["nlb", "alb"], var.balancer)
    error_message = "balancer должен быть \"nlb\" или \"alb\"."
  }
}

variable "instance_count" {
  type        = number
  default     = 3
  description = "Размер группы ВМ (fixed_scale)"
}

variable "disk_size_gb" {
  type        = number
  default     = 5
  description = "Размер загрузочного HDD-диска, ГиБ (образ LAMP требует не меньше 3). Квота зоны: 20 ГиБ HDD на всё"
}
