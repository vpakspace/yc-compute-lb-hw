###--- бакет Object Storage ---###
# Сам бакет создаётся от имени провайдера (IAM-токен SA terraform, роли editor хватает),
# поэтому ключи доступа в этом ресурсе не нужны.
resource "yandex_storage_bucket" "this" {
  bucket = var.bucket_name

  # Картинку нужно отдавать любому из интернета, но список объектов бакета показывать не нужно:
  #   read = true  — объекты читаются анонимно (GET https://<bucket>.storage.yandexcloud.net/<key>);
  #   list = false — перечень ключей в бакете анонимам недоступен.
  anonymous_access_flags {
    read = true
    list = false
  }

  # При destroy удалить вместе с содержимым: иначе непустой бакет не удалится.
  force_destroy = true
}

###--- картинка ---###
# Объекты в бакет пишутся через S3 API, поэтому здесь нужен статический ключ storage-sa.
resource "yandex_storage_object" "picture" {
  bucket       = yandex_storage_bucket.this.bucket
  key          = var.picture_key
  source       = "${path.module}/${var.picture_file}"
  content_type = "image/png"
  # Без source_hash провайдер сравнивает только путь к файлу: правка картинки не попала бы в бакет.
  source_hash = filemd5("${path.module}/${var.picture_file}")

  access_key = yandex_iam_service_account_static_access_key.storage.access_key
  secret_key = yandex_iam_service_account_static_access_key.storage.secret_key

  depends_on = [time_sleep.wait_for_iam]
}

locals {
  # Адрес, по которому картинка открывается из интернета; он же вставляется в страницу на ВМ.
  picture_url = "https://${yandex_storage_bucket.this.bucket_domain_name}/${yandex_storage_object.picture.key}"
}
