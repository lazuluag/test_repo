############################################
# Creates a PEM (and OpenSSH) formatted private key.
############################################

#https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key
resource "tls_private_key" "instance_ssh" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

############################################
# Object Storage service: Uploads private key to Object Storage
############################################

#https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/objectstorage_object
resource "oci_objectstorage_object" "private_key" {
  #Required
  bucket     = oci_objectstorage_bucket.bucket.name
  content    = tls_private_key.instance_ssh.private_key_pem
  namespace  = data.oci_objectstorage_namespace.ns.namespace
  object     = "instance_private_key.pem"

  depends_on = [oci_objectstorage_bucket.bucket]
}

############################################
# Data Source: Oracle Linux Image
############################################

#https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/core_images
data "oci_core_images" "oracle_linux" {
  #Required
  compartment_id           = var.compartment_ocid
  
  #Optional
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var._oci_instance.shape.name
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

############################################
# Data Source: Availability Domains
############################################

#https://registry.terraform.io/providers/oracle/oci/latest/docs/data-sources/identity_availability_domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

############################################
# The template_file data source renders a template from a template string
############################################

#https://registry.terraform.io/providers/hashicorp/template/latest/docs/data-sources/file
data "template_file" "user_data" {
  template = file("${path.module}/templatefile/user_data.sh")

  vars = {
    bucket_name        = oci_objectstorage_bucket.bucket.name
    oci_config_content = file("${path.module}/.oci/config")
    oci_key_content    = file("${path.module}/.oci/key.pem")
    env = templatefile("${path.module}/templatefile/.env.tmpl", {
      compartment_ocid                       = var.compartment_ocid
      autonomous_database_admin_password     = var.autonomous_database_admin_password
      autonomous_database_db_name            = var._oci_autonomous_database.db_name
      autonomous_database_developer_password = var.autonomous_database_developer_password
      autonomous_database_wallet_password    = var.autonomous_database_wallet_password
      namespace                              = data.oci_objectstorage_namespace.ns.namespace
      bucket_name                            = oci_objectstorage_bucket.bucket.name
      region                                 = var.region
    })
  }
}

############################################
# Instance Configuration 
############################################
resource "oci_core_instance_configuration" "instance_config" {
  compartment_id = var.compartment_ocid
  display_name   = "${var._oci_instance.display_name}-config"

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id      = var.compartment_ocid
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      shape               = var._oci_instance.shape.name

      shape_config {
        ocpus         = var._oci_instance.shape.ocpus
        memory_in_gbs = var._oci_instance.shape.memory_in_gbs
      }

      source_details {
        source_type = "image"
        image_id   = data.oci_core_images.oracle_linux.images[0].id
      }

      create_vnic_details {
        subnet_id        = oci_core_subnet.subnet.id
        assign_public_ip = true
      }

      metadata = {
        ssh_authorized_keys = tls_private_key.instance_ssh.public_key_openssh
        user_data           = base64encode(data.template_file.user_data.rendered)
      }
    }
  }
}

############################################
# Instance Pool
############################################
resource "oci_core_instance_pool" "app_pool" {
  compartment_id            = var.compartment_ocid
  instance_configuration_id = oci_core_instance_configuration.instance_config.id
  size                      = 1
  display_name              = "${var._oci_instance.display_name}-instance-pool"

  placement_configurations {
    availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
    primary_subnet_id   = oci_core_subnet.subnet.id
  }

  # Auto-registro en LB backend sets
  load_balancers {
    backend_set_name = oci_load_balancer_backend_set.backend_set_streamlit.name
    load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
    port             = 8501
    vnic_selection   = "PrimaryVnic"
  }

  load_balancers {
    backend_set_name = oci_load_balancer_backend_set.audio_backend_set.name
    load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
    port             = 8000
    vnic_selection   = "PrimaryVnic"
  }
}


############################################
# Autoscaling Configuration
############################################
resource "oci_autoscaling_auto_scaling_configuration" "autoscaling_config" {
  compartment_id      = var.compartment_ocid
  display_name        = "${var._oci_instance.display_name}-autoscale"
  cool_down_in_seconds = 300
  is_enabled          = true

  auto_scaling_resources {
    id   = oci_core_instance_pool.app_pool.id
    type = "instancePool"
  }

  policies {

    capacity {
      initial = 1
      min     = 1
      max     = 5
    }

    policy_type = "threshold"
    rules {
      display_name = "scale_up_rule"
      action {
        type = "CHANGE_COUNT_BY"
        value = 1
      }
      metric {
        metric_type = "CPU_UTILIZATION"
        threshold {
          operator = "GT"
          value    = 70
        }
      }
    }

    rules {
      display_name = "scale_down_rule"
      action {
        type = "CHANGE_COUNT_BY"
        value = -1
      }
      metric {
        metric_type = "CPU_UTILIZATION"
        threshold {
          operator = "LT"
          value    = 30
        }
      }
    }
  }

}

