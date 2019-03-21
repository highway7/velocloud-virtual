variable "velocloud_port" {
  description = "The port the edge will use"
  default = 2426
}

variable "velocloud_activation_code" {
  description = "Activation code from the portal"
  default = "JE87-MYZL-VH6Y-CWWR"
}

variable "vco_hostname" {
  default = "vco160-usca1.velocloud.net"
  description = "VCO this edge is associated with"
}

variable "vpc_cidr_block" {
  default = "10.50.0.0/16"
}


variable "public_cidr" {
  default = "10.50.0.0/24"
}

variable "priv1_cidr" {
  default = "10.50.10.0/24"
}

variable "priv2_cidr" {
  default = "10.50.11.0/24"
}