<div align="center">

```
╔══════════════════════════════════════════════════════════════════╗
║          GITOPS · TERRAFORM · ATLANTIS · AWS ECS FARGATE         ║
╚══════════════════════════════════════════════════════════════════╝
```

# Arquitetura GitOps para Infraestrutura como Código

**Atlantis como Orquestrador de Terraform na AWS**

*Trabalho de Conclusão de Curso — Engenharia de Infraestrutura / Cloud Computing*

---

[![Terraform](https://img.shields.io/badge/Terraform-1.11.4-7B42BC?style=flat-square&logo=terraform&logoColor=white)](https://terraform.io)
[![Atlantis](https://img.shields.io/badge/Atlantis-v0.42.0-1E88E5?style=flat-square)](https://runatlantis.io)
[![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-FF9900?style=flat-square&logo=amazon-aws&logoColor=white)](https://aws.amazon.com)
[![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%2FCD-2088FF?style=flat-square&logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![License](https://img.shields.io/badge/Licença-Acadêmica-4CAF50?style=flat-square)](./LICENSE)

</div>

---

## Índice

- [Visão Geral](#-visão-geral)
- [Princípios GitOps](#-princípios-gitops)
- [Arquitetura](#️-arquitetura)
- [Estrutura do Repositório](#-estrutura-do-repositório)
- [Pré-requisitos](#-pré-requisitos)
- [Guia de Implantação](#-guia-de-implantação)
- [Fluxo GitOps com Pull Requests](#-fluxo-gitops-com-pull-requests)
- [Pipeline CI/CD](#️-pipeline-cicd)
- [Testes de Validação](#-testes-de-validação)
- [Solução de Problemas](#-solução-de-problemas)
- [Destruição e Recriação](#-destruição-e-recriação)
- [Justificativas Técnicas](#-justificativas-técnicas)
- [Comparativo de Ferramentas](#-comparativo-de-ferramentas)
- [Referências](#-referências)

---

## 🔭 Visão Geral

Este repositório implementa uma **arquitetura GitOps de produção** para gerenciamento de Infraestrutura como Código (IaC), utilizando **Terraform** como linguagem declarativa e **Atlantis** como orquestrador de workflows, hospedado em **AWS ECS Fargate**.

Todo o ciclo de vida da infraestrutura — desde a proposta de mudança até a aplicação na nuvem — é governado por **Pull Requests**, garantindo rastreabilidade, reversibilidade e separação clara de responsabilidades.

```
  Desenvolvedor          GitHub                 Atlantis              AWS
      │                    │                       │                   │
      ├── git push ──────► │                       │                   │
      │                    ├── CI Actions ───────► ✓ fmt/validate      │
      │                    │                       │                   │
      │                    ├── webhook ───────────►│                   │
      │                    │                       ├── terraform plan  │
      │                    │◄── plan comment ──────│                   │
      │                    │                       │                   │
      ├── atlantis apply ──►│                       │                   │
      │                    ├── webhook ───────────►│                   │
      │                    │                       ├── terraform apply►│
      │                    │◄── apply comment ─────│                   │
      │                                                       Estado → S3
```

---

## 📐 Princípios GitOps

A solução foi construída sobre os **quatro princípios GitOps** definidos pela [CNCF / OpenGitOps](https://opengitops.dev):

| # | Princípio | Implementação neste projeto |
|:---:|---|---|
| **1** | **Declarativo** | Todo o estado desejado é descrito em arquivos `.tf` versionados no Git. |
| **2** | **Versionado e Imutável** | O Git é a única fonte de verdade — cada mudança é um commit rastreável e auditável. |
| **3** | **Pull-Based** | Mudanças são aplicadas a partir de eventos de Pull Request, sem execução manual de CLI. |
| **4** | **Reconciliação Contínua** | O Atlantis detecta desvios entre estado real e declarado e planeja a correção automaticamente. |

---

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Account                                │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    VPC: tcc-gitops                           │  │
│  │                                                              │  │
│  │  ┌─────────────────────┐    ┌──────────────────────────┐   │  │
│  │  │   Subnet Pública    │    │    Subnet Privada         │   │  │
│  │  │                     │    │                           │   │  │
│  │  │  ┌───────────────┐  │    │  ┌─────────────────────┐ │   │  │
│  │  │  │  ALB (HTTP)   │  │    │  │   EC2 via ASG       │ │   │  │
│  │  │  └───────┬───────┘  │    │  │   (App Nginx)       │ │   │  │
│  │  │          │          │    │  └─────────────────────┘ │   │  │
│  │  │  ┌───────▼───────┐  │    └──────────────────────────┘   │  │
│  │  │  │  ECS Fargate  │  │                                    │  │
│  │  │  │  [Atlantis]   │  │    ┌──────────────────────────┐   │  │
│  │  │  └───────────────┘  │    │  S3  ·  tfstate           │   │  │
│  │  └─────────────────────┘    │  DynamoDB  ·  state lock  │   │  │
│  │                              └──────────────────────────┘   │  │
│  │                              ┌──────────────────────────┐   │  │
│  │                              │  Secrets Manager         │   │  │
│  │                              │  CloudWatch · CloudTrail │   │  │
│  │                              └──────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### Camadas da Arquitetura

| Camada | Recursos AWS | Responsabilidade |
|---|---|---|
| **Orquestração** | ECS Fargate · ALB · Secrets Manager | Executa Atlantis em container serverless; recebe webhooks e orquestra `plan`/`apply`. |
| **Estado Remoto** | S3 (versionado) · DynamoDB | Backend do Terraform com versionamento, criptografia SSE e state locking pessimista. |
| **Rede** | VPC · Subnets · Internet Gateway | Isolamento de rede — Atlantis em subnet pública, aplicação em subnet privada. |
| **CI** | GitHub Actions | Valida formatação, sintaxe, boas práticas e vulnerabilidades a cada push/PR. |
| **Observabilidade** | CloudWatch Logs · CloudTrail | Logs centralizados do Atlantis e auditoria completa de chamadas de API AWS. |

---

## 📁 Estrutura do Repositório

```
tcc-gitops-atlantis/
│
├── .github/
│   └── workflows/
│       └── terraform-ci.yml        # Pipeline CI: fmt · validate · lint · sec
│
├── terraform/
│   ├── modules/                    # Módulos reutilizáveis
│   │   ├── networking/             # VPC, subnets, IGW, route tables
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── compute/                # Launch Template + Auto Scaling Group
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │
│   ├── environments/
│   │   ├── atlantis-infra/         # Infra do Atlantis (ECS, ALB, IAM, Secrets)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── backend.tf
│   │   │   └── terraform.tfvars.example
│   │   └── dev/                    # Ambiente de exemplo — aplicação Nginx
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── backend.tf
│   │
│   └── backend-bootstrap/          # Provisionamento único: S3 + DynamoDB
│       ├── main.tf
│       └── terraform.tfvars.example
│
├── atlantis/
│   └── atlantis.yaml               # Projetos, autoplan e políticas de apply
│
├── docs/
│   ├── architecture-diagram.png
│   └── screenshots/                # Evidências dos cenários de teste
│
├── .gitignore
└── README.md
```

---

## ✅ Pré-requisitos

| Ferramenta | Versão | Finalidade |
|---|---|---|
| **Terraform** | ≥ 1.6.0 | Provisionamento de infraestrutura |
| **AWS CLI** | ≥ 2.x | Autenticação e configuração da conta AWS |
| **Git** | qualquer | Versionamento e fluxo GitOps |
| **Conta GitHub** | — | Repositório, webhooks e GitHub Actions |
| **GitHub PAT** | escopos: `repo`, `admin:repo_hook` | Autenticação do Atlantis com a API do GitHub |
| **AWS Free Tier** | — | Execução sem custo significativo |

---

## 🚀 Guia de Implantação

> **Ordem obrigatória:** `backend` → `atlantis-infra` → `webhook` → `dev`

---

### Passo 1 — Backend Bootstrap

Cria o bucket S3 e a tabela DynamoDB que armazenam o estado remoto de **todos** os ambientes. Execute apenas uma vez por conta AWS.

```powershell
cd terraform/backend-bootstrap

# Configure o nome único do bucket (use seu Account ID para garantir unicidade global)
cp terraform.tfvars.example terraform.tfvars
# Edite: bucket_name = "tcc-tfstate-<SEU-ACCOUNT-ID>"

terraform init
terraform apply -auto-approve
```

> ⚠️ **Mantenha este bucket durante todo o ciclo de vida do projeto.** O custo é negligenciável e o histórico de estados é irreversível se destruído.

---

### Passo 2 — Infraestrutura do Atlantis

Provisiona o Atlantis no ECS Fargate junto com ALB, Secrets Manager e IAM Roles.

```powershell
cd ../environments/atlantis-infra

cp terraform.tfvars.example terraform.tfvars
# Preencha obrigatoriamente:
#   github_user           = "seu-usuario"
#   github_token          = "ghp_..."
#   github_webhook_secret = "segredo-aleatorio-forte"

terraform init
terraform apply -auto-approve
```

Após o apply, anote o output do ALB:

```
Outputs:

alb_dns_name = "atlantis-alb-123456789.us-east-1.elb.amazonaws.com"
```

---

### Passo 3 — Webhook no GitHub

1. Acesse: **Repositório → Settings → Webhooks → Add webhook**
2. Configure os campos:

```
Payload URL   →  http://<alb_dns_name>/events
Content type  →  application/json
Secret        →  <github_webhook_secret>
Events        →  ✅ Pull requests     ✅ Issue comments
```

3. Clique em **Add webhook** — o ping inicial deve retornar `200 OK`. ✅

---

### Passo 4 — Ambiente de Exemplo (dev)

Provisiona uma VPC e uma instância EC2 via ASG executando Nginx — o ambiente-alvo do fluxo GitOps.

```powershell
cd ../dev
terraform init
terraform apply -auto-approve
```

Após o apply, acesse o IP público da instância no Console AWS para validar o servidor Nginx.

---

## 🔄 Fluxo GitOps com Pull Requests

O Atlantis monitora os diretórios configurados no `atlantis.yaml`. Qualquer PR que altere arquivos nesses diretórios aciona o fluxo completo automaticamente.

```
┌──────────────────────────────────────────────────────────────┐
│  CICLO DE VIDA DE UMA MUDANÇA DE INFRAESTRUTURA              │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  $ git checkout -b feature/minha-alteracao                  │
│  $ vim terraform/environments/dev/main.tf                   │
│  $ git add . && git commit -m "feat: atualiza Nginx"        │
│  $ git push origin feature/minha-alteracao                  │
│  → Abra o Pull Request                                       │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  GitHub Actions (CI)               ~2 min           │    │
│  │  ✅ terraform fmt -check                            │    │
│  │  ✅ terraform validate                              │    │
│  │  ✅ tflint                                          │    │
│  │  ✅ tfsec                                           │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │ webhook automático                  │
│  ┌────────────────────▼────────────────────────────────┐    │
│  │  Atlantis                                           │    │
│  │  🤖 terraform plan                                  │    │
│  │  💬 Comenta resultado completo no PR                │    │
│  └────────────────────┬────────────────────────────────┘    │
│                       │ revisão + aprovação                 │
│  → Comente no PR: atlantis apply                            │
│                       │                                     │
│  ┌────────────────────▼────────────────────────────────┐    │
│  │  Atlantis                                           │    │
│  │  ⚡ terraform apply                                 │    │
│  │  💬 Resultado comentado no PR                       │    │
│  │  🔒 Estado persistido no S3                         │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

> **Requisito para apply:** o PR deve estar aprovado e sem conflitos de merge — configurável via `atlantis.yaml`.

---

## ⚙️ Pipeline CI/CD

**Arquivo:** `.github/workflows/terraform-ci.yml`
**Gatilho:** push ou Pull Request com alterações em `terraform/**`

```
┌────────────────────────────────────────────────────────────────┐
│  GitHub Actions — Estágios do Pipeline                        │
│                                                               │
│  ┌───────────────┐   ┌───────────────┐   ┌────────────────┐  │
│  │   VALIDATE    │   │     LINT      │   │   SECURITY     │  │
│  │               │   │               │   │                │  │
│  │ fmt -check    │──►│   tflint      │──►│    tfsec       │  │
│  │ init          │   │  --recursive  │   │ soft_fail=false│  │
│  │ validate      │   │  --min-sev    │   │                │  │
│  │               │   │    =error     │   │                │  │
│  └───────────────┘   └───────────────┘   └────────────────┘  │
│                                                               │
│  ✗ Qualquer falha bloqueia o merge do PR automaticamente     │
│  ✓ plan e apply são responsabilidade exclusiva do Atlantis   │
└────────────────────────────────────────────────────────────────┘
```

| Job | Ferramentas | Objetivo |
|---|---|---|
| **Validate** | `terraform fmt -check` · `terraform init -backend=false` · `terraform validate` | Garantir formatação e sintaxe corretas do HCL. |
| **Lint** | `tflint --recursive --minimum-failure-severity=error` | Verificar boas práticas estruturais e padrões de módulos. |
| **Security** | `tfsec` com `soft_fail=false` | Bloquear configurações inseguras antes do merge. |

---

## 🧪 Testes de Validação

| Cenário | Objetivo | Resultado Esperado |
|---|---|---|
| **Provisionamento Automatizado** | Validar fluxo declarativo e versionado via PR. | Atlantis comenta o plan; apply provisiona a infra na AWS sem intervenção manual. |
| **State Locking** | Demonstrar serialização de operações concorrentes. | Segundo PR simultâneo é bloqueado com mensagem `Error: state locked`. |
| **Drift Detection** | Validar reconciliação contínua após alteração manual no console. | Novo plan detecta o desvio e planeja a correção para realinhar o estado. |
| **Bloqueio de Segurança** | Impedir código vulnerável de chegar ao apply. | `tfsec` falha no CI e bloqueia o merge do PR com regras inseguras. |
| **Auditoria Completa** | Rastreabilidade de ponta a ponta. | Histórico do PR + comentários do Atlantis + registros no CloudTrail. |

---

## 🛠️ Solução de Problemas

| Sintoma | Causa Provável | Solução |
|---|---|---|
| `openpgp: key expired` no CI | Versão desatualizada do Terraform no workflow. | Atualize `terraform_version` para `1.11.4` no arquivo YAML. |
| `InvalidRequestException` no Secrets Manager | Segredo em estado `pending deletion`. | Execute `aws secretsmanager delete-secret --secret-id atlantis-secrets --force-delete-without-recovery` |
| Atlantis não comenta no PR | Webhook mal configurado ou `atlantis.yaml` ausente na `main`. | Verifique a URL do webhook e o status do ping no GitHub. Confirme o arquivo na branch. |
| `Error: Saved plan is stale` | Estado foi alterado por operação externa. | Execute `atlantis plan` novamente, depois `atlantis apply`. |
| EC2 sem IP público | ASG usando sub-rede privada. | Altere o módulo `compute` para sub-redes públicas e force recriação com `terraform taint`. |

---

## ♻️ Destruição e Recriação

### Destruir os ambientes (mantendo o backend)

```powershell
# Ordem obrigatória: inversa à criação

cd terraform/environments/dev
terraform destroy -auto-approve

cd ../atlantis-infra
terraform destroy -auto-approve
```

### Destruir o backend bootstrap

> ⚠️ **Ação irreversível:** apaga todo o histórico de estados. Execute somente ao encerrar definitivamente o projeto.

```powershell
cd ../../backend-bootstrap
terraform destroy -auto-approve
```

### Recriar do zero

```
1. terraform apply  →  backend-bootstrap
2. terraform apply  →  atlantis-infra
3. Atualizar a URL do webhook no GitHub com o novo alb_dns_name
4. terraform apply  →  dev  (ou via PR para exercitar o fluxo completo)
```

---

## 📝 Justificativas Técnicas

### Por que ECS Fargate em vez de EC2 para o Atlantis?

```
✅ Serverless      — sem gerenciamento de SO ou aplicação de patches de segurança
✅ Segurança       — sem acesso SSH; superfície de ataque mínima
✅ Custo           — cobrança por segundo de execução; ideal para workloads intermitentes
✅ Imutabilidade   — atualizações = nova task definition; sem mutação do ambiente
```

### Por que Auto Scaling Group mesmo com `desired_capacity = 1`?

```
✅ Self-healing    — instância substituída automaticamente em caso de falha
✅ Imutabilidade   — mudanças no Launch Template geram novas instâncias, não patches
✅ Escalabilidade  — pronto para crescimento horizontal com alteração mínima
✅ GitOps puro     — demonstra reconciliação contínua de infraestrutura computacional
```

### Por que Atlantis em vez de Terraform Cloud?

```
✅ Controle total  — self-hosted, open-source, zero vendor lock-in
✅ GitOps nativo   — cada plan/apply é um comentário imutável e auditável no PR
✅ Custo zero      — sem licenciamento por workspace ou recurso gerenciado
✅ Transparência   — código-fonte aberto; comportamento totalmente inspecionável
```

---


## 📄 Referências

- [OpenGitOps — CNCF Specification](https://opengitops.dev)
- [Documentação oficial do Atlantis](https://www.runatlantis.io/docs/)
- [Terraform Best Practices](https://www.terraform-best-practices.com)
- [AWS ECS Fargate Developer Guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [tfsec — Static Analysis for Terraform](https://aquasecurity.github.io/tfsec)
- [tflint — Terraform Linter](https://github.com/terraform-linters/tflint)

---

<div align="center">

```
╔══════════════════════════════════════════════════╗
║               Julia Santos                      ║
║   TCC — Engenharia de Infraestrutura / Cloud    ║
║   github.com/juliasantss/tcc-gitops-atlantis    ║
╚══════════════════════════════════════════════════╝
```

*"Infrastructure as Code is not about scripts — it's about engineering discipline."*

</div>
