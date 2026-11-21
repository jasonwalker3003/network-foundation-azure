variable "env" {
  type = string
}
variable "prefix" {
  type = string
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "address_space" {
  description = "The spoke's /16, e.g. 10.20.0.0/16"
  type        = string
  validation {
    condition     = can(cidrhost(var.address_space, 0)) && endswith(var.address_space, "/16")
    error_message = "Give a valid /16 range."
  }
}
variable "hub_vnet_id" {
  type = string
}
variable "hub_vnet_name" {
  type = string
}
variable "bastion_subnet_cidr" {
  type = string
}
variable "tags" {
  type = map(string)
}
