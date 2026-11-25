###--- сервисные аккаунты ---###
# Два отдельных аккаунта с минимальными ролями вместо «всё от editor»:
#   ig-sa      — от его имени Instance Group создаёт и удаляет ВМ, диски и target group балансировщика;
#   storage-sa — его статический ключ нужен, чтобы положить картинку в бакет (объекты пишутся через S3 API).
#
# ⚠️ Назначать роли (`yandex_resourcemanager_folder_iam_member`) может только аккаунт с правом
# `resourcemanager.folders.updateAccessBindings`. У SA `terraform` роль editor его не включает, поэтому перед первым
# apply владелец облака на время выдаёт ему admin на folder, а после apply снимает (команды — в README, «Как запустить»).

resource "yandex_iam_service_account" "ig" {
  name        = "ig-sa"
  description = "Instance Group lamp-group: управление ВМ и target group балансировщика"
}

resource "yandex_iam_service_account" "storage" {
  name        = "storage-sa"
  description = "Загрузка картинки в бакет Object Storage"
}

locals {
  # compute.editor        — создавать/удалять ВМ и диски группы;
  # vpc.user              — подключать ВМ к подсети;
  # vpc.publicAdmin       — выдавать ВМ публичные адреса (nat = true в шаблоне). ГИПОТЕЗА, не проверена: без неё группа
  #                         25 минут подряд получала PERMISSION_DENIED на folder и пересоздавала ВМ в цикле;
  # load-balancer.editor  — создавать target group для сетевого балансировщика (блок load_balancer группы ВМ);
  # alb.editor            — то же для Application Load Balancer (блок application_load_balancer, доп. часть задания).
  ig_roles = ["compute.editor", "vpc.user", "vpc.publicAdmin", "load-balancer.editor", "alb.editor"]
}

resource "yandex_resourcemanager_folder_iam_member" "ig" {
  for_each  = toset(local.ig_roles)
  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.ig.id}"
}

# storage.editor достаточно, чтобы писать объекты. Версионирование и ACL бакета (они требуют storage.admin)
# нам не нужны: публичный доступ включается флагом бакета `anonymous_access_flags` (см. storage.tf).
resource "yandex_resourcemanager_folder_iam_member" "storage" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.storage.id}"
}

resource "yandex_iam_service_account_static_access_key" "storage" {
  service_account_id = yandex_iam_service_account.storage.id
  description        = "Статический ключ storage-sa для загрузки объектов в бакет"
}

# Роли в YC раздаются асинхронно: сразу после назначения операции этим аккаунтом падают с AccessDenied.
# Пауза после всех назначений — и только потом группа ВМ и загрузка объекта.
resource "time_sleep" "wait_for_iam" {
  depends_on = [
    yandex_resourcemanager_folder_iam_member.ig,
    yandex_resourcemanager_folder_iam_member.storage,
  ]
  create_duration = "20s"
}
