variable "velocloud_port" {
  description = "The port the edge will use"
  default = 2426
}

variable "velocloud_activation_code" {
  description = "Activation code from the portal"
  default = "HLX6-CZ9V-FR5S-B5ZR"
}

variable "vco_hostname" {
  default = "vco160-usca1.velocloud.net"
  description = "VCO this edge is associated with"
}