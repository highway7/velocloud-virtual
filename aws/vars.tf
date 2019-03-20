variable "velocloud_port" {
  description = "The port the edge will use"
  default = 2426
}

variable "velocloud_activation_code" {
  description = "Activation code from the portal"
  default = "ARVJ-FQCX-XVBH-8H8Z"
}

variable "vco_hostname" {
  default = "vco160-usca1.velocloud.net"
  description = "VCO this edge is associated with"
}

variable "vpc_cidr_block" {
  default = "10.50.0.0/23"
}


variable "public_cidr" {
  default = "10.50.0.0/24"
}

variable "private_cidr" {
  default = "10.50.1.0/24"
}
