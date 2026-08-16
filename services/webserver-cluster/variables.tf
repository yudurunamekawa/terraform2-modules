variable "cluster_name" {
  type = string
}

variable "db_remote_state_bucket" {
  type = string
}

variable "db_remote_state_key" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "server_port" {
  type    = number
  default = 8080
}

variable "key_name" {
  type = string
}

variable "custom_tags" {
  type    = map(string)
  default = {}
}
