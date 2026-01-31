locals {
  ssh      = "ubuntu:${var.ssh_public_key}"
  platform = "standard-v3"
  ubuntu   = data.yandex_compute_image.ubuntu.id
}

resource "yandex_compute_instance" "nat" {
  name        = "hw2-nat"
  platform_id = local.platform

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.nat.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.nat.id]
  }

  metadata = {
    ssh-keys = local.ssh
  }
}

resource "yandex_compute_instance" "clickhouse" {
  name        = "hw2-clickhouse"
  platform_id = local.platform

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = local.ubuntu
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private.id
    security_group_ids = [yandex_vpc_security_group.private.id]
  }

  metadata = {
    ssh-keys  = local.ssh
    user-data = file("${path.module}/cloud-init/clickhouse.yaml")
  }

  depends_on = [yandex_compute_instance.nat]
}

resource "yandex_compute_instance" "logbroker" {
  count       = 2
  name        = "hw2-logbroker-${count.index + 1}"
  platform_id = local.platform

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = local.ubuntu
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private.id
    security_group_ids = [yandex_vpc_security_group.private.id]
  }

  metadata = {
    ssh-keys  = local.ssh
    user-data = templatefile("${path.module}/cloud-init/logbroker.yaml", {
      clickhouse_ip  = yandex_compute_instance.clickhouse.network_interface.0.ip_address
      python_code_b64 = base64encode(file("${path.module}/files/main.py"))
    })
  }

  depends_on = [yandex_compute_instance.nat, yandex_compute_instance.clickhouse]
}

resource "yandex_compute_instance" "nginx" {
  name        = "hw2-nginx"
  platform_id = local.platform

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = local.ubuntu
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.nginx.id]
  }

  metadata = {
    ssh-keys  = local.ssh
    user-data = templatefile("${path.module}/cloud-init/nginx.yaml", {
      backend1 = yandex_compute_instance.logbroker[0].network_interface.0.ip_address
      backend2 = yandex_compute_instance.logbroker[1].network_interface.0.ip_address
    })
  }

  depends_on = [yandex_compute_instance.logbroker]
}
