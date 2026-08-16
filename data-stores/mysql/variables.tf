variable "db_identifier" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_port" {
  type    = number
  default = 3306
}
