# Credentials from ~/.aws/credentials
provider "aws" {
  profile = "cbts"
  region  = "us-east-1"
}

# Viptela 18.3.0 AMI ami-1c333e63

data "aws_availability_zones" "all" {}

# Whip up a VPC
resource "aws_vpc" "vpc" {
  cidr_block = "${var.vpc_cidr_block}"

  tags = {
    Name = "Velocloud VPC Playground"
  }
}

# Let's have that VPC ID
output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}

# Add Internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "Internet gateway"
  }
}

resource "aws_default_route_table" "pub_rt" {
  default_route_table_id = "${aws_vpc.vpc.default_route_table_id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  tags = {
    Name = "Velocloud Public Table"
  }
}

# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = "${aws_vpc.vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block        = "${var.public_cidr}"

  tags = {
    Name = "Velocloud Public Subnet"
  }
}

# Associate public subnet with its route table
resource "aws_route_table_association" "pub_sub_ass" {
  subnet_id      = "${aws_subnet.public_subnet.id}"
  route_table_id = "${aws_default_route_table.pub_rt.id}"
}

# Create private route table 1
resource "aws_route_table" "priv_rt1" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "Velocloud Private RT 1 - Management Facing"
  }
}

# And private subnet 1
resource "aws_subnet" "priv1_subnet" {
  vpc_id            = "${aws_vpc.vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block        = "${var.priv1_cidr}"

  tags = {
    Name = "Velocloud Private Subnet 1"
  }
}

# Associate private_subnet subnet with its route table
resource "aws_route_table_association" "priv1_sub_ass" {
  subnet_id      = "${aws_subnet.priv1_subnet.id}"
  route_table_id = "${aws_route_table.priv_rt1.id}"
}

# Create private route table 2
resource "aws_route_table" "priv_rt2" {
  vpc_id     = "${aws_vpc.vpc.id}"
  depends_on = ["aws_network_interface.vce_lan"]

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = "${aws_network_interface.vce_lan.id}"
  }

  tags = {
    Name = "Velocloud Private RT 2 - LAN Facing"
  }
}

# And private subnet 2
resource "aws_subnet" "priv2_subnet" {
  vpc_id            = "${aws_vpc.vpc.id}"
  availability_zone = "us-east-1d"
  cidr_block        = "${var.priv2_cidr}"

  tags = {
    Name = "Velocloud Private Subnet 2"
  }
}

# Associate private_subnet subnet with its route table
resource "aws_route_table_association" "priv2_sub_ass" {
  subnet_id      = "${aws_subnet.priv2_subnet.id}"
  route_table_id = "${aws_route_table.priv_rt2.id}"
}

# Create security group
resource "aws_security_group" "allow_velocloud" {
  name        = "allow_velocloud"
  description = "Allow "
  vpc_id      = "${aws_vpc.vpc.id}"

  ingress {
    from_port   = "${var.velocloud_port}"
    to_port     = "${var.velocloud_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = "8"
    to_port     = "0"
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "allow_all"
  }
}

data "template_file" "cloud-config" {
  template = <<YAML
#cloud-config
velocloud:
  vce:
    vco: "vco160-usca1.velocloud.net"
    activation_code: "${var.velocloud_activation_code}"
    vco_ignore_cert_errors: false
YAML
}

output "userdata" {
  value = "${data.template_file.cloud-config.rendered}"
}

# Deploy vedge
resource "aws_instance" "velocloud-edge" {
  ami                    = "ami-da7a56cc"
  instance_type          = "m4.xlarge"
  key_name               = "Craig"
  vpc_security_group_ids = ["${aws_security_group.allow_velocloud.id}"]
  subnet_id              = "${aws_subnet.priv1_subnet.id}"
  source_dest_check      = false
  user_data              = "${base64encode(data.template_file.cloud-config.rendered)}"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "Velocloud Virtual Edge"
  }
}

output "vce-eth0-private-ip" {
  value = "${aws_instance.velocloud-edge.private_ip}"
}

# Create an ENI for eth1 Velocloud transport interface
resource "aws_network_interface" "transport" {
  subnet_id         = "${aws_subnet.public_subnet.id}"
  security_groups   = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false

  attachment {
    instance     = "${aws_instance.velocloud-edge.id}"
    device_index = 1
  }

  tags {
    Name = "Velocloud Transport Interface (GE2 / eth1)"
  }
}

#Create an ENI for Velocloud LAN interface
resource "aws_network_interface" "vce_lan" {
  subnet_id         = "${aws_subnet.priv2_subnet.id}"
  security_groups   = ["${aws_security_group.allow_velocloud.id}"]
  source_dest_check = false

  attachment {
    instance     = "${aws_instance.velocloud-edge.id}"
    device_index = 2
  }

  tags {
    Name = "Velocloud LAN Interface (GE3 / eth2)"
  }
}

# Create EIP for Velocloud transport interface
resource "aws_eip" "transport" {
  vpc               = true
  network_interface = "${aws_network_interface.transport.id}"

  tags {
    Name = "Velocloud Transport Int GE3"
  }
}

# Let's have that public IP
output "vce_eip" {
  value = "${aws_eip.transport.public_ip}"
}

# Deploy jumpbox
resource "aws_instance" "jumpbox" {
  ami           = "ami-02da3a138888ced85"
  instance_type = "t1.micro"
  key_name      = "Craig"

  network_interface {
    device_index         = 0
    network_interface_id = "${aws_network_interface.jump_priv_int.id}"
  }

  network_interface {
    device_index         = 1
    network_interface_id = "${aws_network_interface.jump_pub_int.id}"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "Velocloud Jumpbox"
  }
}

resource "aws_network_interface" "jump_priv_int" {
  subnet_id       = "${aws_subnet.priv1_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]

  tags = {
    Name = "VCE Jumpbox private interface"
  }
}

resource "aws_network_interface" "jump_pub_int" {
  subnet_id       = "${aws_subnet.public_subnet.id}"
  security_groups = ["${aws_security_group.allow_velocloud.id}"]

  tags = {
    Name = "Velocloud Jumpbox public interface"
  }
}

# Create EIP for reaching Jumpbox
resource "aws_eip" "jumpbox_eip" {
  vpc               = true
  network_interface = "${aws_network_interface.jump_pub_int.id}"

  provisioner "local-exec" {
    command = "scp -i ~/.ssh/craig.pem ~/.ssh/craig.pem ec2-user@${self.public_ip}:/home/ec2-user/.ssh"
  }
}

# Let's have that public IP
output "jumpbox_eip" {
  value = "${aws_eip.jumpbox_eip.public_ip}"
}

resource "aws_instance" "Linux-01" {
  ami                    = "ami-02da3a138888ced85"
  instance_type          = "t1.micro"
  key_name               = "Craig"
  vpc_security_group_ids = ["${aws_security_group.allow_velocloud.id}"]
  subnet_id              = "${aws_subnet.priv2_subnet.id}"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "Velocloud Linux Test Workload"
  }
}
