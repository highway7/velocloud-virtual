variable "vsphere_user" {
  default = "administrator@ridge.local"
}
variable "vsphere_password" {}
variable "vsphere_server" {
  default = "vcenter.ridge.local"
}
variable "vsphere_dc" {
  default = "Ridge"
}
variable "vsphere_datastore" {
  default = "RAID"
}