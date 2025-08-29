############################################
# Create Flexible Load Balancer
############################################
resource "oci_load_balancer_load_balancer" "flexible_lb" {
  compartment_id = var.compartment_ocid
  display_name   = var._lb_name
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 100
  }

  subnet_ids = [oci_core_subnet.subnet.id]

  reserved_ips {
    id = var.lb_reserved_ip_id
  }
}

############################################
# Streamlit's Backend Set (Port 8501)
############################################
resource "oci_load_balancer_backend_set" "backend_set_streamlit" {
  name             = "backendset-streamlit"
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTP"
    url_path    = "/"
    port        = 8501
    return_code = 200
  }
}

############################################
# Audio Backend's Backend Set (Port 8000)
############################################
resource "oci_load_balancer_backend_set" "audio_backend_set" {
  name             = "backendset-audio"
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTP"
    url_path    = "/health"
    port        = 8000
    return_code = 200
  }
}

############################################
# TLS Certificate for HTTPS
############################################
resource "oci_load_balancer_certificate" "lb_certificate" {
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  certificate_name = "app-cert"

	private_key        = file("${path.module}/templatefile/key_ca.pem")
	public_certificate = file("${path.module}/templatefile/cert.pem")

}


############################################
# HTTPS Listener with Rule Set
############################################
# Path Route Set
resource "oci_load_balancer_path_route_set" "https_path_routes" {
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  name             = "https_path_routes"

  path_routes {
    path             = "/ws/audio*"
    backend_set_name = oci_load_balancer_backend_set.audio_backend_set.name
    path_match_type {
      match_type = "PREFIX_MATCH"
    }
  }

  path_routes {
    path             = "/*"
    backend_set_name = oci_load_balancer_backend_set.backend_set_streamlit.name
    path_match_type {
      match_type = "PREFIX_MATCH"
    }
  }
}


resource "oci_load_balancer_listener" "https_listener" {
  load_balancer_id         = oci_load_balancer_load_balancer.flexible_lb.id
  name                     = "https-listener"
  default_backend_set_name = oci_load_balancer_backend_set.backend_set_streamlit.name
  port                     = 443
  protocol                 = "HTTP"

  ssl_configuration {
    certificate_name        = oci_load_balancer_certificate.lb_certificate.certificate_name
    verify_peer_certificate = false
  }

  path_route_set_name = oci_load_balancer_path_route_set.https_path_routes.name
}

############################################
# HTTP → HTTPS Redirect Rule Set
############################################
resource "oci_load_balancer_rule_set" "http_redirect_ruleset" {
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  name             = "ruleset"

  items {
    action = "REDIRECT"

    redirect_uri {
      protocol = "HTTPS"
      port     = 443
    }

    conditions {
      attribute_name  = "PATH"
      attribute_value = "/*"
      operator        = "PREFIX_MATCH"
    }


  }
}

############################################
# HTTP Listener (Port 80) with Redirect
############################################
resource "oci_load_balancer_listener" "http_listener" {
  load_balancer_id         = oci_load_balancer_load_balancer.flexible_lb.id
  name                     = "http-listener"
  default_backend_set_name = oci_load_balancer_backend_set.backend_set_streamlit.name
  port                     = 80
  protocol                 = "HTTP"

  rule_set_names = [oci_load_balancer_rule_set.http_redirect_ruleset.name]
}

############################################
# Backends: Streamlit (Port 8501)
############################################
resource "oci_load_balancer_backend" "backend_streamlit" {
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  backend_set_name = oci_load_balancer_backend_set.backend_set_streamlit.name
  ip_address       = oci_core_instance.linux_instance.private_ip
  port             = 8501
  weight           = 1
}

############################################
# Backends: Audio (Port 8000)
############################################
resource "oci_load_balancer_backend" "backend_audio" {
  load_balancer_id = oci_load_balancer_load_balancer.flexible_lb.id
  backend_set_name = oci_load_balancer_backend_set.audio_backend_set.name
  ip_address       = oci_core_instance.linux_instance.private_ip
  port             = 8000
  weight           = 1
}