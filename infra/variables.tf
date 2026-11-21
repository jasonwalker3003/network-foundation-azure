variable "prefix" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,11}$", var.prefix))
    error_message = "Use 3-11 lowercase letters or digits."
  }
}

# Lab switches: costly parts exist only while they're true.
variable "enable_test_vms" {
  type    = bool
  default = false
}
variable "enable_private_endpoint" {
  type    = bool
  default = false
}
variable "enable_bastion" {
  type    = bool
  default = false
}
