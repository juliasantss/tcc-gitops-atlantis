# main.tf - Infraestrutura do Atlantis (ECS Fargate + ALB)

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================
# 1. MÓDULO DE REDE (VPC E SUBNETS)
# ============================================
module "networking" {
  source = "../../modules/networking"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  environment          = "atlantis"
}

# ============================================
# 2. SECURITY GROUPS
# ============================================

# SG do ALB (entrada pública)
resource "aws_security_group" "alb_sg" {
  name        = "atlantis-alb-sg"
  description = "Security group for Atlantis ALB"
  vpc_id      = module.networking.vpc_id

  ingress {
    description = "HTTP from internet (for testing)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "atlantis-alb-sg" }
}

# SG do Atlantis (entrada apenas do ALB)
resource "aws_security_group" "atlantis_sg" {
  name        = "atlantis-sg"
  description = "Security group for Atlantis container"
  vpc_id      = module.networking.vpc_id

  ingress {
    description     = "Atlantis webhook from ALB"
    from_port       = 4141
    to_port         = 4141
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "atlantis-sg"
    Test = "validar PR"
  }
}

# ============================================
# 3. APPLICATION LOAD BALANCER (ALB)
# ============================================
resource "aws_lb" "atlantis" {
  name               = "atlantis-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.networking.public_subnet_ids

  tags = { Name = "atlantis-alb" }
}

resource "aws_lb_target_group" "atlantis" {
  name        = "atlantis-tg"
  port        = 4141
  protocol    = "HTTP"
  vpc_id      = module.networking.vpc_id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = { Name = "atlantis-tg" }
}

# Listener HTTP (único, sem HTTPS)
resource "aws_lb_listener" "atlantis_http" {
  load_balancer_arn = aws_lb.atlantis.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.atlantis.arn
  }
}

# ============================================
# 4. ECS CLUSTER E SERVIÇO (FARGATE)
# ============================================
resource "aws_ecs_cluster" "atlantis" {
  name = "atlantis-cluster"
}

# IAM Roles
resource "aws_iam_role" "execution_role" {
  name = "atlantis-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_role_policy" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name = "atlantis-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Política da Task Role – ATUALIZADA COM PERMISSÕES DE ESCRITA NO ECS E IAM:PASSROLE
resource "aws_iam_role_policy" "task_policy" {
  name = "atlantis-task-policy"
  role = aws_iam_role.task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 (state)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::tcc-tfstate-*",
          "arn:aws:s3:::tcc-tfstate-*/*"
        ]
      },
      # DynamoDB (locking)
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/terraform-locks"
      },
      # Secrets Manager
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret"
        ]
        Resource = aws_secretsmanager_secret.atlantis.arn
      },
      # CloudWatch Logs – permissão total
      {
        Effect = "Allow"
        Action = [
          "logs:*"
        ]
        Resource = "arn:aws:logs:us-east-1:775615219077:log-group:*"
      },
      # IAM Roles (leitura)
      {
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:ListRoles",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = [
          aws_iam_role.execution_role.arn,
          aws_iam_role.task_role.arn
        ]
      },
      # IAM PassRole (necessário para ECS assumir as roles)
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.execution_role.arn,
          aws_iam_role.task_role.arn
        ]
      },
      # ECS (leitura e escrita)
      {
        Effect   = "Allow"
        Action   = "ecs:*"
        Resource = "*"
      },
      # Permissões para provisionar recursos (infraestrutura alvo)
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "vpc:*",
          "autoscaling:*",
          "elasticloadbalancing:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Permissão adicional para a Execution Role ler segredos
resource "aws_iam_role_policy" "execution_role_secrets_policy" {
  name = "atlantis-execution-secrets-policy"
  role = aws_iam_role.execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          aws_secretsmanager_secret.atlantis.arn
        ]
      }
    ]
  })
}

# Task Definition
resource "aws_ecs_task_definition" "atlantis" {
  family                   = "atlantis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name      = "atlantis"
    image     = "ghcr.io/runatlantis/atlantis:v0.42.0"
    essential = true
    portMappings = [{
      containerPort = 4141
      protocol      = "tcp"
    }]
    environment = [
      { name = "ATLANTIS_GH_USER", value = var.github_user },
      { name = "ATLANTIS_GH_WEBHOOK_SECRET", value = var.github_webhook_secret },
      { name = "ATLANTIS_REPO_ALLOWLIST", value = "github.com/${var.github_user}/tcc-gitops-atlantis" },
      { name = "ATLANTIS_LOG_LEVEL", value = "debug" },
      { name = "ATLANTIS_URL", value = "http://${aws_lb.atlantis.dns_name}" },
      { name = "TF_VAR_github_user", value = var.github_user },
      { name = "TF_VAR_github_token", value = var.github_token },
      { name = "ATLANTIS_TERRAFORM_VERSION", value = "1.11.4" }
    ]
    secrets = [
      { name = "ATLANTIS_GH_TOKEN", valueFrom = "${aws_secretsmanager_secret.atlantis.arn}:token::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.atlantis.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "atlantis"
      }
    }
  }])
}

resource "aws_ecs_service" "atlantis" {
  name            = "atlantis-service"
  cluster         = aws_ecs_cluster.atlantis.id
  task_definition = aws_ecs_task_definition.atlantis.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.networking.public_subnet_ids
    security_groups  = [aws_security_group.atlantis_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.atlantis.arn
    container_name   = "atlantis"
    container_port   = 4141
  }

  depends_on = [aws_lb_listener.atlantis_http]
}

# ============================================
# 5. SEGREDOS NO SECRETS MANAGER
# ============================================
resource "aws_secretsmanager_secret" "atlantis" {
  name = "atlantis-secrets"
}

resource "aws_secretsmanager_secret_version" "atlantis" {
  secret_id = aws_secretsmanager_secret.atlantis.id
  secret_string = jsonencode({
    token = var.github_token
  })
}

# ============================================
# 6. CLOUDWATCH LOG GROUP
# ============================================
resource "aws_cloudwatch_log_group" "atlantis" {
  name              = "/ecs/atlantis"
  retention_in_days = 7
}